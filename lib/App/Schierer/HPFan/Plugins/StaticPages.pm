use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require YAML::PP;

package App::Schierer::HPFan::Plugins::StaticPages {
  use Mojo::Base 'Mojolicious::Plugin';
  use Mojo::Base 'App::Schierer::HPFan::Logger::MojoLog4Perl', -role;
  use Mojo::Base 'App::Schierer::HPFan::Role::Markdown', -role;
  use Mojo::Base 'App::Schierer::HPFan::Role::Navigation', -role;
  use Carp;

  my %static_routes;

  sub register ($plugin, $app, $config) {
    $plugin->logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $plugin->logger->category()
    ));

    # Add helper to check if a static route exists
    $app->helper(
      static_route_name_for => sub ($self, $path) {
        return $static_routes{$path};    # undef if not present
      }
    );

    foreach my $static_entry ($plugin->build_routes($app)) {
      $plugin->logger->info(sprintf(
        'Adding route "%s" for file "%s"',
        $static_entry->{route},
        $static_entry->{path}
      ));
      $app->routes->get($static_entry->{route})->to(
        cb => sub ($self) {
          my $rp = $self->req->url->path->to_string;

          # Remove trailing slash from pages
          if ($rp =~ qr{/$}) {
            my $canonical = $rp;
            $canonical =~ s{/$}{};
            if (length($canonical)) {
              return $self->redirect_to($canonical, 301);
            }
          }
          return $self->render_markdown_file($static_entry->{path});
        }
      );
      $plugin->add_navigation_item({
        title => $static_entry->{file}->{title},
        path  => $static_entry->{path},
        order => $static_entry->{file}->{order},
      });
    }
    $app->config(after_static => 1);
  }

  sub build_routes ($self, $app) {
    my $pages_dir =
      Mojo::File::Share::dist_dir('App::Schierer::HPFan')->child('pages');

    my @added_routes;

    my $rule = Path::Iterator::Rule->new;
    $rule->file->readable->nonempty->name('*.md');
    my $iter = $rule->iter($pages_dir);
    while (my $file = $iter->()) {
      my $file_path     = Mojo::File->new($file);
      my $relative_path = $file_path->to_rel($pages_dir);
      my $route_path    = $self->file_path_to_route($relative_path);
      $self->logger->debug(
        "Considering static route: $route_path for file: $relative_path");

      my $parsedFile = $self->parse_markdown_frontmatter($file_path);
      if ($parsedFile) {
        my $normalized_route = lc($route_path);
        my $has_conflict     = 0;

        my $existing_nav = $self->get_existing_navigation_items() || {};
        $self->logger->debug(sprintf('comparing against %s existing nav entries.',
          scalar keys %$existing_nav));
        foreach my $existing_path (keys %$existing_nav) {
          if (fc($existing_path) eq fc($normalized_route)) {
            $has_conflict = 1;
            $self->logger->debug(sprintf(
              'Skipping static page navigation for "%s"'
                . ' - conflicts with existing "%s"',
              $route_path, $existing_path,
            ));
            last;
          }
        }

        unless ($has_conflict) {
          $self->logger->debug(
            sprintf('Registering "%s" as static route, no conflicts present',
              $route_path)
          );
          push @added_routes,
            {
            route => $route_path,
            path  => $file_path,
            file  => $parsedFile,
            };
        }
      }
    }
    return @added_routes;
  }

  # Convert file path to route path
  sub file_path_to_route {
    my ($self, $path) = @_;

    # Remove file extension
    $path =~ s/\.md$//;

    # Special case for root index.md
    if ($path eq 'index') {
      return '/';
    }

    # Handle other index files in subdirectories
    $path =~ s/\/index$//;

    # Ensure path starts with /
    $path = "/$path" unless $path =~ /^\//;

    return $path;
  }

}
1;

__END__
