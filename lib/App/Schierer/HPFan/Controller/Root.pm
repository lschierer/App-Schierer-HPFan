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

has site_logo => (
  is      => 'ro',
  default => '',
);

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
    $self->add_navigation_route($route, $entry->{title}, { order => 10 });

    $self->router->add(
      $route,
      {
        to => sub ($self, $ctx) {
          return $self->render_markdown_page($entry->{path}, $route);
        },
        action => 'http.get',
      }
    );
  }

  $self->logger->info("Registered " . scalar(@routes) . " static Root routes");
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

    $tree{$route} = {
      title => $title,
      path  => $file,
      route => $route,
    };
    $self->logger->debug(
      sprintf('registering tree object %s', Data::Printer::np($tree{$route})));
  }
  return \%tree;
}

1;
__END__
