#!/usr/bin/env perl
use v5.42.0;
use utf8::all;
use Encode qw(encode_utf8);
use lib '../PAGI-WebServer/lib';
use lib 'lib';
use PAGI::WebServer;
use PAGI::WebServer::Router;
use PAGI::WebServer::Markdown;
use PAGI::WebServer::Navigation;
use PAGI::WebServer::Template;
require App::Schierer::HPFan::Person;
require App::Schierer::HPFan::Family;
require App::Schierer::HPFan::History;
require App::Schierer::HPFan::ClassLists;
use PAGI::Server;
use Future::AsyncAwait;
use Path::Tiny;
use IO::Async::Loop;

my $framework = PAGI::WebServer->new(config_file => 'config.yml');

$framework->setup_logging;

my $markdown = PAGI::WebServer::Markdown->new;
my $template = PAGI::WebServer::Template->new(
    template_dir => 'templates',
    include_path => ['templates', 'templates/partials']
);
my $pages_dir = path('share/pages');

# Create navigation
my $nav = PAGI::WebServer::Navigation->new;

# Create family handler (initialize gramps once)
my $family_handler = App::Schierer::HPFan::Family->new(navigation => $nav);

# Create person handler with navigation (shares gramps with family handler)
my $person_handler = App::Schierer::HPFan::Person->new(
    navigation => $nav,
    gramps => $family_handler->gramps,  # Share gramps instance
);
my $history_handler = App::Schierer::HPFan::History->new(
    template   => $template,
    navigation => $nav,
    gramps     => $family_handler->gramps,  # Share gramps instance
);

# Create class lists handler
my $classlists_handler = App::Schierer::HPFan::ClassLists->new(
    gramps => $family_handler->gramps,  # Share gramps instance
);

# Register base navigation routes
sub register_markdown_routes {
    my ($nav, $pages_dir) = @_;

    my @md_files = $pages_dir->visit(
        sub {
            my ($path) = @_;
            return unless $path->is_file && $path->basename =~ /\.md$/;

            # Convert file path to route path
            my $rel_path = $path->relative($pages_dir);
            my $route = "/$rel_path";
            $route =~ s/\.md$//;
            $route =~ s|/index$||;  # Remove /index for index files

            # Parse frontmatter to get title and order
            my $content = $path->slurp_utf8;
            my ($frontmatter, $markdown_content) = $markdown->parse_frontmatter($content);

            # Use title from frontmatter, or generate from filename
            my $title = $frontmatter->{title};
            if (!$title) {
                $title = $path->basename;
                $title =~ s/\.md$//;
                $title =~ s/[-_]/ /g;
                $title =~ s/\b(\w)/\U$1/g;  # Capitalize words
            }

            # Get order from frontmatter (sidebar.order), or use default
            my $order = $frontmatter->{sidebar}{order} // 50;

            # Add route to navigation
            $nav->add_route($route, $title, { order => $order });
        },
        { recurse => 1 }
    );
}

register_markdown_routes($nav, $pages_dir);

$nav->add_route('/Harrypedia', 'Harrypedia', { order => 1 });
$nav->add_route('/Harrypedia/people', 'People', { order => 1 });
$nav->add_route('/Harrypedia/places', 'Places', { order => 2 });
$nav->add_route('/Harrypedia/events', 'Events', { order => 3 });
$nav->add_route('/Fan Fiction', 'Fan Fiction', { order => 2 });
$nav->add_route('/Searches', 'Searches', { order => 3 });
$nav->add_route('/Bookmarks', 'Bookmarks', { order => 4 });

# Add special "Unknown" surname route
$nav->add_route('/Harrypedia/people/Unknown', 'Genealogical Gaps - Unknown Surnames', { order => 999 });

# Register routes for all family surnames and their members (highest priority)
my $surnames = $family_handler->get_all_surnames();
for my $surname (@$surnames) {
    my $route_path = '/Harrypedia/people/' . $surname;
    $nav->add_route($route_path, "$surname Family", { order => 100 });

    # Register individual family members
    my $family_members = $family_handler->get_people_by_surname($surname);
    for my $person (@$family_members) {
        my $primary_name = $person->primary_name;
        next unless $primary_name;

        my $given = $primary_name->first_name // '';
        next unless $given;

        my $person_route = "/Harrypedia/people/$surname/$given";
        $nav->add_route($person_route, $given, { order => 110 });
    }
}

# Register people with unknown surnames
my $unknown_people = $family_handler->get_people_with_unknown_surname();
for my $person (@$unknown_people) {
    my $primary_name = $person->primary_name;
    my $given = $primary_name ? ($primary_name->first_name // '') : '';

    my $display_name = $given || $person->gramps_id || 'Unknown';
    my $person_route = "/Harrypedia/people/Unknown/$display_name";
    $nav->add_route($person_route, $display_name, { order => 110 });
}



# Create router
my $router = PAGI::WebServer::Router->new;

# Add route for root
$router->get(
  '/' => async sub {
    my ($scope, $receive, $send) = @_;

    my $index_file = $pages_dir->child('index.md');
    if ($index_file->exists) {
      my $html  = $markdown->render($index_file->stringify);
      my $bytes = encode_utf8($html);

      await $send->({
        type    => 'http.response.start',
        status  => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
      });
      await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
      });
    }
    else {
      await $send->({
        type    => 'http.response.start',
        status  => 404,
        headers => [['content-type', 'text/plain']],
      });
      await $send->({
        type => 'http.response.body',
        body => 'Not Found',
        more => 0,
      });
    }
  }
);

# Add person routes (higher priority than markdown)
$router->get('/Harrypedia/people/*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    my ($surname, $given_name) = $path =~ m{^/Harrypedia/people/([^/]+)/(.+)$};

    if ($surname && $given_name) {
        # URL decode the names
        $surname =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $given_name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        eval {
            # Check for static markdown content for this person
            my $static_content = '';
            my $person_md = $pages_dir->child("Harrypedia", "people", $surname, "$given_name.md");
            if ($person_md->exists) {
                $static_content = $markdown->render($person_md->stringify);
            }

            # Pass current path for navigation
            my $html = $person_handler->render_person_page($surname, $given_name, $static_content, $path);

            if ($html) {
                my $bytes = encode_utf8($html);

                await $send->({
                    type => 'http.response.start',
                    status => 200,
                    headers => [['content-type', 'text/html; charset=utf-8']],
                });
                await $send->({
                    type => 'http.response.body',
                    body => $bytes,
                    more => 0,
                });
                return;
            }
        };

        if ($@) {
            warn "Error rendering person page: $@";
            await $send->({
                type => 'http.response.start',
                status => 500,
                headers => [['content-type', 'text/plain']],
            });
            await $send->({
                type => 'http.response.body',
                body => "Internal Server Error: $@",
                more => 0,
            });
            return;
        }
    }

    # Try as family listing (single segment after /people/)
    my ($surname_only) = $path =~ m{^/Harrypedia/people/([^/]+)$};

    if ($surname_only) {
        # URL decode the surname
        $surname_only =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        eval {
            # Check for static markdown content for this family
            my $static_content = '';
            my $family_md = $pages_dir->child("Harrypedia", "people", "$surname_only.md");
            if ($family_md->exists) {
                $static_content = $markdown->render($family_md->stringify);
            }

            # Pass current path for navigation
            my $html = $family_handler->render_family_page($surname_only, $static_content, $path);

            if ($html) {
                my $bytes = encode_utf8($html);

                await $send->({
                    type => 'http.response.start',
                    status => 200,
                    headers => [['content-type', 'text/html; charset=utf-8']],
                });
                await $send->({
                    type => 'http.response.body',
                    body => $bytes,
                    more => 0,
                });
                return;
            }
        };

        if ($@) {
            warn "Error rendering family page: $@";
            await $send->({
                type => 'http.response.start',
                status => 500,
                headers => [['content-type', 'text/plain']],
            });
            await $send->({
                type => 'http.response.body',
                body => "Internal Server Error: $@",
                more => 0,
            });
            return;
        }
    }

    # Person/Family not found - check for markdown fallback
    my $path_for_md = $path;
    $path_for_md =~ s|^/||;  # Remove leading slash

    # Try exact path first
    my $md_file = $pages_dir->child("$path_for_md.md");

    # If not found, try as directory with index.md
    if (!$md_file->exists) {
        $md_file = $pages_dir->child($path_for_md, 'index.md');
    }

    if ($md_file->exists) {
        my ($frontmatter, $content_html) = $markdown->render_with_frontmatter($md_file->stringify);

        # Use title from frontmatter or generate from path
        my $title = $frontmatter->{title};
        if (!$title) {
            $title = $path_for_md;
            $title =~ s|/| - |g;
            $title =~ s/[-_]/ /g;
            $title =~ s/\b(\w)/\U$1/g;
        }

        # Check if autoindex is requested
        if ($frontmatter->{autoindex}) {
            use PAGI::WebServer::AutoIndex;
            my $autoindex = PAGI::WebServer::AutoIndex->new(
                pages_dir => $pages_dir,
                markdown  => $markdown,
            );
            my $entries = $autoindex->generate_directory_index($md_file->parent);
            if ($entries && @$entries) {
                my $autoindex_html = $template->render('partials/directory-list.tt', { entries => $entries });
                $content_html .= "\n<hr class=\"spectrum-Divider spectrum-Divider--sizeM\">\n" . $autoindex_html;
            }
        }

        # Post-process class list tables if present
        if ($content_html =~ /<classlisttable/i) {
            $content_html = $classlists_handler->render_classlist_tables($content_html);
        }

        my $current_year = (localtime)[5] + 1900;
        my $navigation_html = $nav->render($path);

        my $vars = {
            content        => $content_html,
            title          => $title,
            current_year   => $current_year,
            css_files      => ['/css/navigation.css', '/css/directory-list.css'],
            sidebar        => 1,
            navigation     => $navigation_html,
        };

        my $html = $template->render(
            'page/markdown.tt',
            $vars,
            { layout => 'layouts/default.tt' }
        );

        my $bytes = encode_utf8($html);

        await $send->({
            type    => 'http.response.start',
            status  => 200,
            headers => [['content-type', 'text/html; charset=utf-8']],
        });
        await $send->({
            type => 'http.response.body',
            body => $bytes,
            more => 0,
        });
        return;
    }

    # No markdown file either - return 404
    await $send->({
        type => 'http.response.start',
        status => 404,
        headers => [['content-type', 'text/plain']],
    });
    await $send->({
        type => 'http.response.body',
        body => 'Person or Family Not Found',
        more => 0,
    });
});

# Add route for CSS files
$router->get('/css/*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    my ($filename) = $path =~ m{^/css/(.+)$};

    if ($filename) {
        my $css_file = path('public/css')->child($filename);

        if ($css_file->exists && $css_file->is_file) {
            my $content = $css_file->slurp_utf8;
            my $bytes = encode_utf8($content);

            await $send->({
                type => 'http.response.start',
                status => 200,
                headers => [['content-type', 'text/css; charset=utf-8']],
            });
            await $send->({
                type => 'http.response.body',
                body => $bytes,
                more => 0,
            });
            return;
        }
    }

    # CSS file not found
    await $send->({
        type => 'http.response.start',
        status => 404,
        headers => [['content-type', 'text/plain']],
    });
    await $send->({
        type => 'http.response.body',
        body => 'CSS Not Found',
        more => 0,
    });
});

# Add dynamic route for markdown files
$router->get(
  '*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    $path =~ s|^/||;    # Remove leading slash

    # Try exact path first
    my $md_file = $pages_dir->child("$path.md");

    # If not found, try as directory with index.md
    if (!$md_file->exists) {
      $md_file = $pages_dir->child($path, 'index.md');
    }

    if ($md_file->exists) {
      my ($frontmatter, $content_html) = $markdown->render_with_frontmatter($md_file->stringify);

      # Use title from frontmatter or generate from path
      my $title = $frontmatter->{title};
      if (!$title) {
        $title = $path;
        $title =~ s|/| - |g;
        $title =~ s/[-_]/ /g;
        $title =~ s/\b(\w)/\U$1/g;
      }

      # Check if autoindex is requested
      if ($frontmatter->{autoindex}) {
        use PAGI::WebServer::AutoIndex;
        my $autoindex = PAGI::WebServer::AutoIndex->new(
          pages_dir => $pages_dir,
          markdown  => $markdown,
        );
        my $entries = $autoindex->generate_directory_index($md_file->parent);
        if ($entries && @$entries) {
          my $autoindex_html = $template->render('partials/directory-list.tt', { entries => $entries });
          $content_html .= "\n<hr class=\"spectrum-Divider spectrum-Divider--sizeM\">\n" . $autoindex_html;
        }
      }

      # Post-process class list tables if present
      if ($content_html =~ /<classlisttable/i) {
        $content_html = $classlists_handler->render_classlist_tables($content_html);
      }

      # Get current year for footer
      my $current_year = (localtime)[5] + 1900;

      # Render navigation
      my $navigation_html = $nav->render($path);

      # Prepare template variables
      my $vars = {
        content        => $content_html,
        title          => $title,
        current_year   => $current_year,
        css_files      => ['/css/navigation.css', '/css/directory-list.css'],
        sidebar        => 1,
        navigation     => $navigation_html,
      };

      # Render with layout
      my $html = $template->render(
        'page/markdown.tt',
        $vars,
        { layout => 'layouts/default.tt' }
      );

      my $bytes = encode_utf8($html);

      await $send->({
        type    => 'http.response.start',
        status  => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
      });
      await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
      });
    }
    else {
      # Check if this is a gap directory (no index.md but has children)
      my $dir_path = $pages_dir->child($path);
      if ($dir_path->is_dir && $dir_path->children) {
        use PAGI::WebServer::AutoIndex;
        my $autoindex = PAGI::WebServer::AutoIndex->new(
          pages_dir => $pages_dir,
          markdown  => $markdown,
        );
        my $entries = $autoindex->generate_directory_index($dir_path);

        # Generate title from path
        my $title = $path;
        $title =~ s|/| - |g;
        $title =~ s/[-_]/ /g;
        $title =~ s/\b(\w)/\U$1/g;

        my $current_year = (localtime)[5] + 1900;
        my $navigation_html = $nav->render($path);

        my $vars = {
          entries        => $entries,
          title          => $title,
          current_year   => $current_year,
          css_files      => ['/css/navigation.css', '/css/directory-list.css'],
          sidebar        => 1,
          navigation     => $navigation_html,
        };

        my $html = $template->render(
          'page/autoindex.tt',
          $vars,
          { layout => 'layouts/default.tt' }
        );

        my $bytes = encode_utf8($html);

        await $send->({
          type    => 'http.response.start',
          status  => 200,
          headers => [['content-type', 'text/html; charset=utf-8']],
        });
        await $send->({
          type => 'http.response.body',
          body => $bytes,
          more => 0,
        });
        return;
      }
      await $send->({
        type    => 'http.response.start',
        status  => 404,
        headers => [['content-type', 'text/plain']],
      });
      await $send->({
        type => 'http.response.body',
        body => 'Not Found',
        more => 0,
      });
    }
  }
);

# Create event loop and server
# Add History timeline route
$router->get('/Harrypedia/History' => async sub {
    my ($scope, $receive, $send) = @_;

    my $html = $history_handler->timeline_handler;
    my $bytes = encode_utf8($html);

    await $send->({
        type => 'http.response.start',
        status => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
    });
    await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
    });
});

my $loop = IO::Async::Loop->new;

my $server = PAGI::Server->new(
  app  => $router->to_app,
  host => '127.0.0.1',
  port => 3001,
);

$loop->add($server);
$server->listen->get;

# Keep the event loop running
$loop->run;
