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
require App::Schierer::HPFan::Bookmarks;
require App::Schierer::HPFan::HPNOFP;
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

# Load site logo SVG
my $logo_file = path('public/images/LukeHPSite.svg');
my $site_logo = '';
if ($logo_file->exists) {
  my $svg_content = $logo_file->slurp_utf8;
  # Strip XML declaration and DOCTYPE
  $svg_content =~ s/^<\?xml[^?]*\?>\s*//;
  $svg_content =~ s/^<!DOCTYPE[^>]*>\s*//;
  # Add class="site-logo" to svg element
  $svg_content =~ s/<svg/<svg class="site-logo"/;
  $site_logo = $svg_content;
}

# Create navigation
my $nav = PAGI::WebServer::Navigation->new;

# Create family handler (initialize gramps once)
my $family_handler = App::Schierer::HPFan::Family->new(
  navigation => $nav,
  site_logo  => $site_logo,
);

# Create person handler with navigation (shares gramps with family handler)
my $person_handler = App::Schierer::HPFan::Person->new(
  navigation     => $nav,
  gramps         => $family_handler->gramps,    # Share gramps instance
  family_handler => $family_handler,
  markdown       => $markdown,
  site_logo      => $site_logo,
);
my $history_handler = App::Schierer::HPFan::History->new(
  template   => $template,
  navigation => $nav,
  gramps     => $family_handler->gramps,        # Share gramps instance
  site_logo  => $site_logo,
);

# Create class lists handler
my $classlists_handler = App::Schierer::HPFan::ClassLists->new(
  gramps => $family_handler->gramps,            # Share gramps instance
);

# Create bookmarks handler
my $bookmarks_handler = App::Schierer::HPFan::Bookmarks->new(
  template   => $template,
  navigation => $nav,
  markdown   => $markdown,
  site_logo  => $site_logo,
);

# Create HPNOFP handler
my $hpnofp_handler = App::Schierer::HPFan::HPNOFP->new(
  template   => $template,
  navigation => $nav,
  site_logo  => $site_logo,
);

# Register base navigation routes
async sub register_markdown_routes {
  my ($nav, $pages_dir) = @_;

  my @md_files = $pages_dir->visit(
    sub {
      my ($path) = @_;
      return unless $path->is_file && $path->basename =~ /\.md$/;

      # Convert file path to route path
      my $rel_path = $path->relative($pages_dir);
      my $route    = "/$rel_path";
      $route =~ s/\.md$//;
      $route =~ s|/index$||;    # Remove /index for index files

      # Parse frontmatter to get title and order
      my $content = $path->slurp_utf8;
      my ($frontmatter, $markdown_content) =
        $markdown->parse_frontmatter($content);

      # Use title from frontmatter, or generate from filename
      my $title = $frontmatter->{title};
      if (!$title) {
        $title = $path->basename;
        $title =~ s/\.md$//;
        $title =~ s/[-_]/ /g;
        $title =~ s/\b(\w)/\U$1/g;    # Capitalize words
      }

      # Get order from frontmatter (sidebar.order) - only if explicitly set
      my $options = {};
      if (defined $frontmatter->{sidebar}{order}) {
        $options->{order} = $frontmatter->{sidebar}{order};
      }

      # Add route to navigation (will default to 999 if no order specified)
      $nav->add_route($route, $title, $options);
    },
    { recurse => 1 }
  );
}

await register_markdown_routes($nav, $pages_dir);

# Note: Most routes are now registered by markdown files with frontmatter controlling order.
# Only add fallback routes here if they don't already exist (no markdown file).

# Create router
my $router = PAGI::WebServer::Router->new;

# Register family routes
await $family_handler->register_routes($nav, $router);

# Register person routes
await $person_handler->register_routes($nav, $router);

# Register history routes
await $history_handler->register_routes($nav, $router);

# Register bookmarks routes
await $bookmarks_handler->register_routes($nav, $router);

# Register HPNOFP routes
await $hpnofp_handler->register_routes($nav, $router);

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

# Add route for CSS files
$router->get(
  '/css/*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    my ($filename) = $path =~ m{^/css/(.+)$};

    if ($filename) {
      my $css_file = path('public/css')->child($filename);

      if ($css_file->exists && $css_file->is_file) {
        my $content = $css_file->slurp_utf8;
        my $bytes   = encode_utf8($content);

        await $send->({
          type    => 'http.response.start',
          status  => 200,
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
      type    => 'http.response.start',
      status  => 404,
      headers => [['content-type', 'text/plain']],
    });
    await $send->({
      type => 'http.response.body',
      body => 'CSS Not Found',
      more => 0,
    });
  }
);

# Add route for JS files
$router->get(
  '/js/*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    my ($filename) = $path =~ m{^/js/(.+)$};

    if ($filename) {
      my $js_file = path('public/js')->child($filename);

      if ($js_file->exists && $js_file->is_file) {
        my $content = $js_file->slurp_utf8;
        my $bytes   = encode_utf8($content);

        # Determine content type based on file extension
        my $content_type = $filename =~ /\.js$/ ? 'application/javascript; charset=utf-8'
                         : $filename =~ /\.map$/ ? 'application/json; charset=utf-8'
                         : 'text/plain; charset=utf-8';

        await $send->({
          type    => 'http.response.start',
          status  => 200,
          headers => [['content-type', $content_type]],
        });
        await $send->({
          type => 'http.response.body',
          body => $bytes,
          more => 0,
        });
        return;
      }
    }

    # JS file not found
    await $send->({
      type    => 'http.response.start',
      status  => 404,
      headers => [['content-type', 'text/plain']],
    });
    await $send->({
      type => 'http.response.body',
      body => 'JS Not Found',
      more => 0,
    });
  }
);

# Add route for image files
$router->get(
  '/images/*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    my ($filename) = $path =~ m{^/images/(.+)$};

    if ($filename) {
      my $img_file = path('public/images')->child($filename);

      if ($img_file->exists && $img_file->is_file) {
        my $content = $img_file->slurp_raw;  # Binary content for images

        # Determine content type based on file extension
        my $content_type = $filename =~ /\.jpe?g$/i ? 'image/jpeg'
                         : $filename =~ /\.png$/i   ? 'image/png'
                         : $filename =~ /\.gif$/i   ? 'image/gif'
                         : $filename =~ /\.svg$/i   ? 'image/svg+xml'
                         : $filename =~ /\.webp$/i  ? 'image/webp'
                         : $filename =~ /\.ico$/i   ? 'image/x-icon'
                         : 'application/octet-stream';

        await $send->({
          type    => 'http.response.start',
          status  => 200,
          headers => [['content-type', $content_type]],
        });
        await $send->({
          type => 'http.response.body',
          body => $content,
          more => 0,
        });
        return;
      }
    }

    # Image file not found
    await $send->({
      type    => 'http.response.start',
      status  => 404,
      headers => [['content-type', 'text/plain']],
    });
    await $send->({
      type => 'http.response.body',
      body => 'Image Not Found',
      more => 0,
    });
  }
);

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
      my ($frontmatter, $content_html) =
        $markdown->render_with_frontmatter($md_file->stringify);

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
          my $autoindex_html = $template->render('partials/directory-list.tt',
            { entries => $entries });
          $content_html .=
            "\n<hr class=\"spectrum-Divider spectrum-Divider--sizeM\">\n"
            . $autoindex_html;
        }
      }

      # Post-process class list tables if present
      if ($content_html =~ /<classlisttable/i) {
        $content_html =
          $classlists_handler->render_classlist_tables($content_html);
      }

      # Get current year for footer
      my $current_year = (localtime)[5] + 1900;

      # Render navigation
      my $navigation_html = $nav->render($path);

      # Prepare template variables
      my $vars = {
        content      => $content_html,
        title        => $title,
        current_year => $current_year,
        css_files    => ['/css/navigation.css', '/css/directory-list.css'],
        sidebar      => 1,
        navigation   => $navigation_html,
        site_logo    => $site_logo,
      };

      # Render with layout
      my $html = $template->render('page/markdown.tt', $vars,
        { layout => 'layouts/default.tt' });

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

        my $current_year    = (localtime)[5] + 1900;
        my $navigation_html = $nav->render($path);

        my $vars = {
          entries      => $entries,
          title        => $title,
          current_year => $current_year,
          css_files    => ['/css/navigation.css', '/css/directory-list.css'],
          sidebar      => 1,
          navigation   => $navigation_html,
          site_logo    => $site_logo,
        };

        my $html = $template->render('page/autoindex.tt', $vars,
          { layout => 'layouts/default.tt' });

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
