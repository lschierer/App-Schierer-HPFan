package App::Schierer::HPFan::Controller::Root;

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
with 'App::Schierer::HPFan::Role::Gramps';
with 'WebFramework::Role::Logger';
extends 'Thunderhorse::Controller';

use Future::AsyncAwait;
require Path::Tiny;
require Path::Iterator::Rule;

has base_dir => (
  is      => 'ro',
  default => sub {
    my $self = shift;
    return Path::Tiny::path($self->app->config->{config}->{markdown_dir});
  },
);

sub build ($self) {
  my $build_start = sprintf('build method for "%s"', __PACKAGE__);
  $self->logger->info($build_start);
  my $tree   = $self->_build_Root_Tree;
  my @routes = sort keys %$tree;

  # Register all routes
  for my $route (@routes) {
    my $entry = $tree->{$route};

    # Add to navigation
    if ($route eq '/Harrypedia') {
      $self->add_navigation_route($route, $entry->{title}, { order => 10 });
    }
    elsif (defined($entry->{order})) {
      $self->add_navigation_route($route, $entry->{title},
        { order => $entry->{order} });
    }
    else {
      $self->add_navigation_route($route, $entry->{title}, { order => 50 });
    }

    $self->router->add(
      $route,
      {
        to => async sub ($self, $ctx) {
          if (Path::Tiny::path($entry->{path})->slurp_utf8 =~ /classlisttable/i)
          {
            my $fm   = $self->parse_markdown_frontmatter($entry->{path});
            my $html = $self->retrieve_rendered_markdown($entry->{path});
            $html = await $self->render_classlist_tables($html);

            my $title = $fm->{title};
            if (!$title) {
              my $path_for_title = $entry->{route};
              $path_for_title =~ s|^/||;
              $title = $path_for_title;
              $title =~ s|/| - |g;
              $title =~ s/[-_]/ /g;
              $title =~ s/\b(\w)/\U$1/g;
            }

            my $current_year = (localtime)[5] + 1900;
            my $sidebar      = $fm->{layout} // 1;
            $sidebar = 0 if ($sidebar =~ /splash/);

            my $vars = {
              content      => $html,
              title        => $title,
              current_year => $current_year,
              css_files    => ['/css/navigation.css'],
              sidebar      => $sidebar,
              nav_html     => $self->render_navigation($entry->{route}),
            };

            return $self->render('page/markdown.tt', $vars);
          }
          else {
            return $self->render_markdown_page($entry->{path}, $route,
              { site_logo => $self->site_logo() });
          }

        },
        action => 'http.get',
      }
    );
  }

  $self->logger->info("Registered " . scalar(@routes) . " static Root routes");

  # Add catch-all route for directory gaps (AutoIndex)
  $self->router->add(
    '*',
    {
      to => sub ($self, $ctx, @args) {
        return $self->handle_directory_gap($ctx);
      },
      action => 'http.get',
    }
  );
}

sub handle_directory_gap ($self, $ctx) {
  my $path = $ctx->req->path;
  $path =~ s|^/||;    # Remove leading slash

  my $dir_path = $self->base_dir->child($path);

  # Check if this is a directory without index.md but has children
  if ( $dir_path->is_dir
    && $dir_path->children
    && !$dir_path->child('index.md')->exists) {
    my $entries = $self->generate_directory_index($dir_path);

    # Generate title from path
    my $title = $path || 'Home';
    $title =~ s|/| - |g;
    $title =~ s/[-_]/ /g;
    $title =~ s/\b(\w)/\U$1/g;

    my $current_year    = (localtime)[5] + 1900;
    my $navigation_html = $self->render_navigation($ctx->req->path);

    my $vars = {
      entries      => $entries,
      title        => $title,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/directory-list.css'],
      sidebar      => 1,
      navigation   => $navigation_html,
      site_logo    => $self->site_logo(),
    };

    return $self->render('page/autoindex.tt', $vars);
  }

  # Not found
  return $self->render(
    'error.tt',
    {
      title        => 'Page Not Found',
      message      => 'The requested page was not found.',
      current_year => (localtime)[5] + 1900,
    }
  );
}

sub _build_Root_Tree ($self) {
  my %tree;

  $self->logger->debug(sprintf('about to iterate over "%s"', $self->base_dir));
  my $rule = Path::Iterator::Rule->new;
  my $next = $rule->file->nonempty->name(qr/\.md/)->iter(
    $self->base_dir,
    {
      depthfirst      => -1,
      follow_symlinks =>  0,
      report_symlinks =>  0,
      sorted          =>  1,
    }
  );
  while (defined(my $file = $next->())) {
    $file = Path::Tiny::path($file);
    $self->logger->debug("Root Controller iterating over '$file'");
    my $fm = $self->parse_markdown_frontmatter($file->absolute);
    unless ($fm) {
      $self->logger->warn("No frontmatter available for '$file'");
      next;
    }
    my $title = $fm->{title} // $file->basename(qr/.md/);
    my $route;
    my $order;

    if ($title =~ /index/) {
      $title = $file->parent->basename;
      my $rel_dir = $file->parent->relative($self->base_dir);
      if ($rel_dir eq '.') {
        # Root bookmarks directory
        $route = '/';
      }
      else {
        $route = "/$rel_dir";
      }
    }
    else {
      $route = $file->relative($self->base_dir)->stringify;
      $route =~ s/(.+)\.md$/\/$1/;
      $route =~ s/\/index$//;
    }

    if (exists $fm->{sidebar} && exists $fm->{sidebar}->{order}) {
      $order = $fm->{sidebar}->{order};
    }

    $tree{$route} = {
      title => $title,
      path  => $file,
      route => $route,
      order => $order,
    };
    $self->logger->debug(
      sprintf('registering tree object %s', Data::Printer::np($tree{$route})));
  }
  return \%tree;
}

1;
__END__
