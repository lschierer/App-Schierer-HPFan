use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require HTML::Element;
use namespace::clean;

package App::Schierer::HPFan::Plugins::Navigation {
  use Mojo::Base 'Mojolicious::Plugin';
  use Carp;
  require Log::Log4perl;

  my %nav_items_by_path;
  my %raw_paths;

  my $rejected_items_by_path = {
    '/policy'         => 1,
    '/policy/privacy' => 1,
    '/index'          => 1,
  };

  sub register ($self, $app, $config) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info("Registering navigation plugin");

    $app->helper(add_navigation_item => \&_add_navigation_item);
    $app->helper(generate_navigation => \&_generate_navigation);

    $app->helper(
      get_existing_navigation_items => sub {
        return \%nav_items_by_path;
      }
    );

  }

  sub _generate_navigation($c, $current_path = undef, $detached = 0) {
    $current_path //= $c->req->url->path->to_string;

    my $nav_element = HTML::Element->new('nav',);
    my $ul          = HTML::Element->new(
      'ul',
      class => sprintf('spectrum-TreeView spectrum-TreeView--sizeM %s',
        $detached ? 'spectrum-TreeView--detached' : '')
    );
    $nav_element->push_content($ul);

    _build_nav_level($ul, \%nav_items_by_path, $current_path, '');

    return $nav_element->as_HTML;
  }

  sub _build_nav_level($parent_ul, $items_hash, $current_path, $parent_path) {
    # Sort items by order
    my @sorted_items =
      sort { $items_hash->{$a}->{order} <=> $items_hash->{$b}->{order} }
      keys %$items_hash;

    for my $item_path (@sorted_items) {
      my $item      = $items_hash->{$item_path};
      my $full_path = $parent_path . $item->{path};

      my $li = HTML::Element->new(
        'li',
        class => sprintf('spectrum-TreeView-item %s',
          $current_path =~ /^\Q$full_path\E/ ? 'is-selected' : ''),
      );
      my $link = HTML::Element->new(
        'a',
        href  => $full_path,
        class => "spectrum-TreeView-itemLink"
      );
      my $titleSpan =
        HTML::Element->new('span', class => "spectrum-TreeView-itemLabel");
      $titleSpan->push_content($item->{title});
      $link->push_content($titleSpan);
      $li->push_content($link);

      # Handle children if they exist
      if ($item->{children} && %{ $item->{children} }) {
      # Check if current path is within this branch by seeing if any child paths
      # are ancestors of the current path
        my $should_be_open =
          _path_contains_current($item->{children}, $current_path, $full_path);

        my $child_ul = HTML::Element->new(
          'ul',
          class => sprintf('spectrum-TreeView spectrum-TreeView--sizeM %s',
            $should_be_open ? 'is-opened' : '',)
        );
        $li->push_content($child_ul);
        _build_nav_level($child_ul, $item->{children}, $current_path,
          $full_path);
      }

      $parent_ul->push_content($li);
    }
  }

  sub _path_contains_current($children_hash, $current_path, $parent_path) {
    for my $child_path (keys %$children_hash) {
      my $full_child_path =
        $parent_path . $children_hash->{$child_path}->{path};

      # If current path starts with this child path, this branch should be open
      if ($current_path =~ /^\Q$full_child_path\E/) {
        return 1;
      }
    }
    return 0;
  }

  sub _add_navigation_item ($c, $item) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);

    unless (ref $item eq 'HASH' && $item->{path}) {
      $logger->error(
        "Invalid item (missing path): " . Data::Printer::np($item));
      return;
    }
    my $path = $item->{path};

    unless (!$rejected_items_by_path->{$path}) {
      $logger->debug("Skipping rejected path $path");
      return;
    }

    unless (exists $item->{title}) {
      $logger->error("Item rejected: missing title for $path");
      return;
    }

    $logger->debug(
      "NAVIGATION: Registering path '$path' with title '$item->{title}'");

    $raw_paths{$path}++;

    if (exists $nav_items_by_path{$path}) {
      my $existing = $nav_items_by_path{$path};
      if (exists $item->{order} && exists $existing->{order}) {
        if ($item->{order} < $existing->{order}) {
          $nav_items_by_path{$path} = $item;
        }
      }
      elsif (exists $item->{order}) {
        $nav_items_by_path{$path} = $item;
      }
      elsif (!exists $existing->{order}) {
        $logger->error("Duplicate navigation item at $path without order");
      }
    }
    else {
      $nav_items_by_path{$path} = $item;
    }

    return 1;
  }

  sub _titleize ($self, $seg) {
    $seg =~ s/_/ /g;
    return join ' ', map { ucfirst lc } split ' ', $seg;
  }

};
1;
__END__
# ABSTRACT: Provides the Main navigation element for App::Schierer::HPFan

# DESCRIPTION

this works with hash objects that conform to

$item = {
  title     => '',
  path      => '',
  order     => 9999,
  children  => {}
};
where
* $item->title contains the page title.
* $item->path contains path segment of a URI to navigate to this item
* $item->order contains where this item should be ordered in a list under its parent, 1 at the top, 9999 at the bottom.
* $item->children contains any nested paths (ie this item is a folder/directory object).
