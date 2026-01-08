package App::Schierer::HPFan::Controller::Bookmarks;

use v5.42.0;
use Mooish::Base -standard;
extends 'Thunderhorse::Controller';
with 'WebFramework::Role::Logger';

use Path::Tiny;
use YAML::XS qw(Load);
use Encode   qw(encode_utf8);

sub build ($self) {
  $self->register_routes($self->router);
}

has site_logo => (
  is      => 'ro',
  default => '',
);

has bookmarks_dir => (
  is      => 'ro',
  default => sub { path('share/Bookmarks') },
);

has bookmarks_tree => (is => 'lazy',);

sub _build_bookmarks_tree ($self) {
  my %tree;

  my $iter = $self->bookmarks_dir->iterator({
    recurse         => 1,
    follow_symlinks => 0,
  });

  while (my $file = $iter->()) {
    next unless $file->is_file && $file->basename =~ /\.yaml$/;

    $self->process_bookmark_file($file, \%tree);
  }

  my @keys = sort keys %tree;
  $self->logger->debug(
    "Built bookmarks tree with " . scalar(@keys) . " entries");

  return \%tree;
}

sub process_bookmark_file ($self, $file, $tree) {
  $self->logger->debug("Processing bookmark file: $file");

  my $content;
  eval {
    my $yaml_str = $file->slurp_raw;
    $content = Load($yaml_str);
  };
  if ($@) {
    $self->logger->error("Error parsing YAML file '$file': $@");
    return;
  }

  unless (ref $content eq 'HASH') {
    $self->logger->warn("Content is not a hash in '$file': " . ref($content));
    return;
  }

  unless ($content->{name}) {
    $self->logger->warn("'name' is required in '$file', ignoring");
    return;
  }

  # Determine title (use 'title' if present, otherwise 'name')
  my $title = $content->{title} // $content->{name};

  # Calculate route path
  my $rel_path = $file->relative($self->bookmarks_dir);
  my $route;

  if ($file->basename eq 'index.yaml') {
    # For index.yaml, route is the directory path
    my $rel_dir = $file->parent->relative($self->bookmarks_dir);
    if ($rel_dir eq '.') {
      # Root bookmarks directory
      $route = '/Bookmarks';
    }
    else {
      $route = "/Bookmarks/$rel_dir";
    }
  }
  else {
    # For regular files, route includes the name from YAML
    my $dir_path = $file->parent->relative($self->bookmarks_dir);
    if ($content->{name} eq 'Bookmarks') {
      $route = '/Bookmarks';
    }
    else {
      $route =
        $dir_path eq '.'
        ? "/Bookmarks/$content->{name}"
        : "/Bookmarks/$dir_path/$content->{name}";
    }
  }

  $self->logger->debug("Route for '$file' is '$route' with title '$title'");

  $tree->{$route} = {
    %$content,
    title => $title,
    path  => $file,
    route => $route,
  };
}

sub register_routes ($self, $router) {
  my $tree   = $self->bookmarks_tree;
  my @routes = sort keys %$tree;

  # Register all routes
  for my $route (@routes) {
    my $entry = $tree->{$route};

    # Add to navigation
    $self->add_navigation_route($route, $entry->{title}, { order => 30 });

    # Determine if this is an index or page route
    if ($entry->{path}->basename eq 'index.yaml') {
      # Index route - shows list of children
      $router->add(
        $route,
        {
          to => sub ($self, $ctx) {
            return $self->bookmark_index($ctx, $entry, \@routes);
          },
          action => 'http.get',
        }
      );
    }
    else {
      # Page route - shows bookmark items
      $router->add(
        $route,
        {
          to => sub ($self, $ctx) {
            return $self->bookmark_page($ctx, $entry);
          },
          action => 'http.get',
        }
      );
    }
  }

  $self->logger->info("Registered " . scalar(@routes) . " bookmark routes");
}

sub bookmark_index ($self, $ctx, $entry, $all_routes) {
  my $current_path = $ctx->req->path;

  # Find direct children of current path
  my @child_entries;
  my $tree = $self->bookmarks_tree;

  for my $route (@$all_routes) {
    next unless $route =~ /^\Q$current_path\E/;
    next if $route eq $current_path;    # Skip self

    # Get relative path
    my $relative = $route;
    $relative =~ s/^\Q$current_path\E\/?//;

    # Skip grandchildren (has more path segments)
    next if $relative =~ m{/};

    # This is a direct child
    my $entry_data = $tree->{$route};
    push @child_entries,
      {
      title => $entry_data->{title} // $entry_data->{name},
      path  => $route,
      };
  }

  @child_entries = sort { $a->{title} cmp $b->{title} } @child_entries;

  # Render comments as markdown if present
  my $comments_html = '';
  if ($entry->{comments}) {
    $comments_html = $self->markdown_string_to_html($entry->{comments});
  }

  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation($current_path);

  my $vars = {
    items        => \@child_entries,
    comments     => $comments_html,
    title        => $entry->{title},
    current_year => $current_year,
    css_files    => ['/css/navigation.css', '/css/directory-list.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo,
  };

  return $self->render('bookmarks/index.tt', $vars);
}

sub bookmark_page ($self, $ctx, $entry) {
  my $current_path = $ctx->req->path;

  # Get items array
  my @items = $entry->{items} ? @{ $entry->{items} } : ();
  @items =
    sort { ($a->{title}{name} // '') cmp($b->{title}{name} // '') } @items;

  # Render top-level comments as markdown if present
  my $comments_html = '';
  if ($entry->{comments}) {
    $comments_html = $self->markdown_string_to_html($entry->{comments});
  }

  # Render each item's comments as markdown
  for my $item (@items) {
    if ($item->{comments}) {
      $item->{comments_html} =
        $self->markdown_string_to_html($item->{comments});
    }
  }

  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation($current_path);

  my $vars = {
    items        => \@items,
    comments     => $comments_html,
    title        => $entry->{title},
    current_year => $current_year,
    css_files    => ['/css/navigation.css', '/css/bookmarks.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo,
  };

  return $self->render('bookmarks/page.tt', $vars);
}

1;
