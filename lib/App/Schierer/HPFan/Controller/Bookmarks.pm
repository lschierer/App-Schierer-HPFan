use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require YAML::PP;
require Scalar::Util;
require Sereal::Encoder;
require Sereal::Decoder;

package App::Schierer::HPFan::Controller::Bookmarks {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  my $logger;

  sub register($self, $app, $config) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    my $distDir      = $app->config('distDir');
    my $BookmarksSrc = $distDir->child('Bookmarks');
    my $baseRoute    = '/Bookmarks';

    my $rule = Path::Iterator::Rule->new;
    my $iter = $rule->file->name(qr/.yaml$/)->iter($BookmarksSrc);

    my $BookmarksTree = {};
    while (my $file_path = $iter->()) {
      $file_path = Mojo::File->new($file_path);
      $self->process_bookmark_file($app, $file_path, $baseRoute,
        $BookmarksTree);

    }
    my @BookmarksKeys = sort keys %{$BookmarksTree};
    $logger->debug("final BookmarksTree: " . Data::Printer::np(@BookmarksKeys));

    $app->helper(
      bookmarks_tree => sub {
        my $encoder         = Sereal::Encoder->new();
        my $serialized_data = $encoder->encode($BookmarksTree);
        my $decoder         = Sereal::Decoder->new();
        return $decoder->decode($serialized_data);
      }
    );
    foreach my $key (@BookmarksKeys) {
      my $entry = $BookmarksTree->{$key};

      if ($entry->{path}->basename eq 'index.yaml') {
        $app->routes->get($key)->to(
          controller => 'Bookmarks',
          action     => 'bookmark_index',
          entry      => $entry,
          allRoutes  => \@BookmarksKeys,
        );
      }
      else {
        $app->routes->get($key)->to(
          controller => 'Bookmarks',
          action     => 'bookmark_page',
          entry      => $entry,
        );
      }

      # Add to navigation
      $app->add_navigation_item({
        title => $entry->{title},
        path  => $key,
        order => 10,
      });
    }

  }

  sub bookmark_index ($c) {
    my $path = $c->req->url->path->to_string;

    # Remove trailing slash from person pages
    if ($path =~ /\/$/) {
      my $canonical = $path;
      $canonical =~ s/\/$//;
      return $c->redirect_to($canonical, 301);
    }

    my $current_route  = $c->current_route;
    my $current_path   = $c->url_for($current_route)->path->to_string;
    my @allRoutes      = @{ $c->stash('allRoutes') };
    my $entry          = $c->stash('entry');
    my $bookmarks_tree = $c->bookmarks_tree();

    $logger->debug("Building index for: '$current_path' with tree: "
        . Data::Printer::np($bookmarks_tree));

    # Find all routes that are direct children of current path
    my @child_entries;

    for my $route (@allRoutes) {
      next unless $route =~ /^\Q$current_path\E/;
      # Skip if this IS the current path (don't include self)
      next if $route eq $current_path;

      # Get the relative path (remove current path prefix)
      my $relative = $route;
      $relative =~ s/^\Q$current_path\E\/?//;

      # Skip if this is a grandchild (has more path segments)
      next if $relative =~ qr{/};

      # This is a direct child
      my $entry_data = $bookmarks_tree->{$route};
      $logger->debug(sprintf(
        'entry data for route "%s" is : %s',
        $route, Data::Printer::np($entry_data)
      ));
      push @child_entries,
        {
        title => $entry_data->{title} || $entry_data->{name},
        path  => $route,
        };
    }

    @child_entries = sort @child_entries;

    $c->stash(
      template => 'bookmarks/index',
      layout   => 'default',
      items    => \@child_entries,
      title    => exists $entry->{title} ? $entry->{title} : $entry->{name},
      comments => $entry->{comments},
    );
    return $c->render;
  }

  sub bookmark_page ($c) {

    my $path = $c->req->url->path->to_string;

    # Remove trailing slash from person pages
    if ($path =~ /\/$/) {
      my $canonical = $path;
      $canonical =~ s/\/$//;
      return $c->redirect_to($canonical, 301);
    }

    my $entry = $c->stash('entry');
    unless ($entry and ref $entry eq 'HASH') {
      $logger->error(
        __PACKAGE__ . "Cannot get entry for " . $c->req->url->to_abs);
      $c->reply->not_found;
    }
    my @items = exists $entry->{items} ? @{ $entry->{items} } : ();
    @items = sort { $a->{title}->{name} cmp $b->{title}->{name} } @items;
    $c->stash(
      layout   => 'default',
      template => 'bookmarks/page',
      title    => $entry->{title},
      comments => exists $entry->{comments} ? $entry->{comments} : '',
      items    => \@items,
    );
    return $c->render;
  }

  sub process_bookmark_file ($self, $app, $file, $baseRoute, $BookmarksTree) {

    $logger->debug(__PACKAGE__ . " process_bookmark_file start for $file");

    $file = Mojo::File->new($file) unless ref $file eq 'Mojo::File';

    my $distDir = $app->config('distDir');

    my $ypp = YAML::PP->new(
      schema       => [qw/ + Perl /],
      yaml_version => ['1.2', '1.1'],
    );
    my $content;
    eval { $content = $ypp->load_string($file->slurp('UTF-8')); };
    if ($@) {
      $logger->error("Error parsing YAML Bookmarks file '$file': $@");
    }
    elsif (ref $content eq 'HASH') {
      my $title = $file->basename('.yaml');
      if ($content->{name}) {
        $title =
          exists $content->{title} ? $content->{title} : $content->{name};
        my $dirPath = $file->dirname->to_abs;
        $dirPath =~ s{$distDir}{};
        my $route;
        if ($file->basename eq 'index.yaml') {
          $route = $file->dirname->to_abs;
          $route =~ s{$distDir}{};
        }
        else {
          $route = sprintf('%s/%s', $dirPath, $content->{name})
            unless $content->{name} eq 'Bookmarks';
        }

        $logger->debug("Route after considering name is $route");
        $logger->debug("Finalized title for '$route' is '$title'");
        $BookmarksTree->{$route}            = $content;
        $BookmarksTree->{$route}->{'title'} = $title;
        $BookmarksTree->{$route}->{'path'}  = $file;
      }
      else {
        $logger->warn(
"name is a required key in a yaml bookmarks file. '$file' will be ignored until it is present."
        );
      }

    }
    else {
      $logger->warn("content is not a hash. " . ref $content);
    }
  }

}
1;
__END__
