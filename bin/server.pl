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
require App::Schierer::HPFan::Person;
require App::Schierer::HPFan::Family;
require App::Schierer::HPFan::History;
use PAGI::Server;
use Future::AsyncAwait;
use Path::Tiny;
use IO::Async::Loop;

my $framework = PAGI::WebServer->new(config_file => 'config.yml');

$framework->setup_logging;
# Create navigation
my $nav = PAGI::WebServer::Navigation->new;

my $markdown = PAGI::WebServer::Markdown->new;

# Create family handler (initialize gramps once)
my $family_handler = App::Schierer::HPFan::Family->new(navigation => $nav);

# Create person handler with navigation (shares gramps with family handler)
my $person_handler = App::Schierer::HPFan::Person->new(
    navigation => $nav,
    gramps => $family_handler->gramps,  # Share gramps instance
);
my $history_handler = App::Schierer::HPFan::History->new;
my $pages_dir = path('share/pages');

# Register base navigation routes
$nav->add_route('/Harrypedia', 'Harrypedia', { order => 1 });
$nav->add_route('/Harrypedia/people', 'People', { order => 1 });
$nav->add_route('/Harrypedia/places', 'Places', { order => 2 });
$nav->add_route('/Harrypedia/events', 'Events', { order => 3 });
$nav->add_route('/Fan Fiction', 'Fan Fiction', { order => 2 });
$nav->add_route('/Searches', 'Searches', { order => 3 });
$nav->add_route('/Bookmarks', 'Bookmarks', { order => 4 });

# Add special "Unknown" surname route
$nav->add_route('/Harrypedia/people/Unknown', 'Genealogical Gaps - Unknown Surnames', { order => 999 });

# Register routes for all family surnames
my $surnames = $family_handler->get_all_surnames();
for my $surname (@$surnames) {
    my $route_path = '/Harrypedia/people/' . $surname;
    $nav->add_route($route_path, "$surname Family", { order => 100 });
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

    # Person/Family not found
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
      my $html  = $markdown->render($md_file->stringify);
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
