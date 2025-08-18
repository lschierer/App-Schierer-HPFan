use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require Scalar::Util;

package App::Schierer::HPFan::Controller::AutoIndex {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  my $logger;

  sub register($self, $app, $config) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    $app->helper(
      generate_directory_index => sub ($c, $path) {
        my $i = $self->_generate_directory_index($path, $app);
        $logger->debug(sprintf(
          'generated index: %s for "%s"', Data::Printer::np($i), $path
        ));
        return $i;
      }
    );

    # Register after StaticPages to catch unhandled directory routes

    my $dist_dir  = $app->config('distDir');
    my $pages_dir = $dist_dir->child('pages');
    $logger->debug(
      __PACKAGE__ . ' starting directory discovery in ' . $pages_dir);

    # Find directories under our target sections that lack index.md
    my $rule = Path::Iterator::Rule->new;
    my $iter = $rule->directory->iter($pages_dir);

    # Register routes for each directory that needs auto-indexing
    while (my $dir_path = $iter->()) {
      $dir_path = Mojo::File->new($dir_path);
      if (-e $dir_path->child('index.md')) {
        $logger->debug("found index for dir_path $dir_path - skipping");
        next;
      }
      if ($dir_path =~ m{/Harrypedia/people/\w+$}) {
        next;
      }
      my $web_path = $dir_path;
      $web_path =~ s/^\Q$pages_dir\E//;    # Remove pages prefix
      $web_path = '/' . $web_path unless $web_path =~ /^\//;

      $logger->info("Registering auto-index route for: '$web_path'");

      $app->routes->get($web_path)->to(
        controller => 'AutoIndex',
        action     => 'auto_index_handler',
        dir_path   => "$dir_path"
      );

      # Add to navigation
      $app->add_navigation_item({
        title => $self->_titleize_path($dir_path->basename),
        path  => $web_path,
        order => 1,
      });
    }

  }

  sub auto_index_handler ($c) {
    $logger->debug(__PACKAGE__ . " auto_index_handler start");

    my $path = $c->req->url->path->to_string;

    # Remove trailing slash from person pages
    if ($path =~ /\/$/) {
      my $canonical = $path;
      $canonical =~ s/\/$//;
      return $c->redirect_to($canonical, 301);
    }

    my $dir_path = Mojo::File->new($c->stash('dir_path'));
    $logger->debug("rendering directory index for $dir_path");
    my $generated_directory = $c->_generate_directory_index($dir_path, $c->app);
    $logger->debug(sprintf(
      'generated_directory is: %s for "%s"',
      Data::Printer::np($generated_directory), $dir_path
    ));
    $c->stash(entries  => $generated_directory);
    $c->stash(layout   => 'default');
    $c->stash(template => 'autoindex');
    $c->stash(title    => $c->_titleize_path($dir_path->basename));
    $c->render;
  }

  sub _needs_auto_index($self, $app, $path) {
    my $dist_dir = $app->config('distDir');
    my $fs_path  = $dist_dir->child('pages' . $path);

    # Check if directory exists but no index.md
    return $fs_path->is_dir && !$fs_path->child('index.md')->exists;
  }

  sub _generate_directory_index($self, $path, $app) {

    $path = Mojo::File->new($path) unless ref $path eq 'Mojo::File';
    $path = $path->dirname if $path->basename eq 'index.md';
    $logger->debug("searching $path");

    my @entries;
    my $distDir = $app->config('distDir');
    if (not defined $distDir) {
      $logger->error(
        "distDir is not defined while generating directory for $path");
    }
    else {
      $logger->debug("discovered distDir $distDir from config");
    }

    foreach my $child ($path->list({ dir => 1 })->each) {
      next if ($child->basename eq 'index.md');
      $logger->debug("inspecting $child");
      if (-d $child) {
        $logger->debug("$child is a directory");
        # Titleize directory name
        my $name = $child->basename;
        $name =~ s/_/ /g;
        $name = join(' ', map { ucfirst lc } split ' ', $name);
        my $route = "$path/" . $child->basename;
        $route =~ s{$distDir/pages}{};
        $logger->debug(sprintf(
          'route "%s" for path "%s"',
          $route, "$path/" . $child->basename
        ));
        push @entries,
          {
          title => $name,
          path  => $route,
          type  => 'directory'
          };
      }
      elsif ($child->basename =~ /\.md$/) {

        $logger->debug("$child is a markdown file");

        # Parse frontmatter for title
        my $frontmatter = $app->parse_markdown_frontmatter($child);

        my $title    = $frontmatter->{title};
        my $basename = $child->basename =~ s/\.md$//r;

        my $route = "$path/$basename" =~ s{$distDir/pages}{}r;
        push @entries,
          {
          title => $title,
          path  => $route,
          type  => 'file'
          };
      }
      else {
        $logger->warn("file with odd extension: $child");
      }
    }

    # Sort entries
    @entries = sort { $a->{title} cmp $b->{title} } @entries;

    $logger->debug("before return, " . Data::Printer::np(@entries));
    return \@entries;
  }

  sub _titleize_path ($self, $seg) {
    $seg =~ s/_/ /g;
    return join ' ', map { ucfirst lc } split ' ', $seg;
  }
}
1;
__END__
