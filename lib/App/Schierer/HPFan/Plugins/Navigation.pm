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
      build_nav_level => sub ($c, @rest) {
        _build_nav_level(@rest);
      }
    );

    $app->helper(
      get_existing_navigation_items => sub {
        return \%raw_paths;
      }
    );

  }

  sub _filesystem_path_to_web_path($c, $file_path) {
    # Get distDir from the application config
    my $dist_dir = $c->app->config('distDir');

    my $web_path = $file_path;

    # Remove the dist_dir/pages prefix
    $web_path =~ s/^\Q$dist_dir\E\/pages//;

    # Remove /index.md suffix (but keep the directory)
    $web_path =~ s/\/index\.md$//;

    # Remove .md extension from other files
    $web_path =~ s/\.md$//;

    # Ensure it starts with / (root-relative)
    $web_path = '/' . $web_path unless $web_path =~ /^\//;

    # Handle the root case
    $web_path = '/' if $web_path eq '';

    return $web_path;
  }

  sub _generate_navigation($c, $current_path = undef, $detached = 0) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $current_path //= $c->req->url->path->to_string;

    my $ul = HTML::Element->new(
      'ul',
      class => sprintf('spectrum-TreeView spectrum-TreeView--sizeM %s',
        $detached ? 'spectrum-TreeView--detached' : '')
    );

    $c->app->build_nav_level($ul, \%nav_items_by_path, $current_path, '');
    $logger->info('current routes are: ' . join('; ', keys %raw_paths));
    return $ul->as_HTML;
  }

  sub _create_placeholder_item($segment_name, $full_path) {
    my $logger      = Log::Log4perl->get_logger(__PACKAGE__);
    my $placeholder = {
      title           => _titleize($segment_name),    # "people" -> "People"
      path            => $full_path,
      order           => 9999,
      children        => {},
      _is_placeholder => 1                            # Mark as placeholder
    };
    $logger->debug("creating placeholder " . Data::Printer::np($placeholder));
    return $placeholder;
  }

  sub _merge_or_add_item($level, $path, $new_item) {
    if (exists $level->{$path}) {
      my $existing = $level->{$path};

      # If existing is a placeholder and new item has real content, upgrade it
      if ($existing->{_is_placeholder} && !$new_item->{_is_placeholder}) {
        # Keep the children from the placeholder, merge in the real content
        $new_item->{children} = $existing->{children} if $existing->{children};
        $level->{$path} = $new_item;
        $raw_paths{$path}++;
      }
      # Handle order precedence for real items
      elsif (!$existing->{_is_placeholder} && !$new_item->{_is_placeholder}) {
        if (exists $new_item->{order} && exists $existing->{order}) {
          if ($new_item->{order} < $existing->{order}) {
            # Keep existing children, use new item data
            $new_item->{children} = $existing->{children}
              if $existing->{children};
            $level->{$path} = $new_item;
            $raw_paths{$path}++;
          }
        }
        elsif (exists $new_item->{order}) {
          $new_item->{children} = $existing->{children}
            if $existing->{children};
          $level->{$path} = $new_item;
          $raw_paths{$path}++;
        }
      }
      # If new item is placeholder but existing is real, keep existing
    }
    else {
      # New item
      $level->{$path} = $new_item;
      $raw_paths{$path}++;
    }
  }

  sub _build_path_hierarchy($path, $item) {
    my @segments      = grep { $_ ne '' } split '/', $path;
    my $current_level = \%nav_items_by_path;
    my $current_path  = '';

    # Build each level of the hierarchy
    for my $i (0 .. $#segments) {
      $current_path .= '/' . $segments[$i];

      if ($i == $#segments) {
        # This is the final segment - the actual item being added
        _merge_or_add_item($current_level, $current_path, $item);
        $raw_paths{$current_path}++ unless $item->{'_is_placeholder'};
      }
      else {
        # This is an intermediate parent - create placeholder if needed
        unless (exists $current_level->{$current_path}) {
          $current_level->{$current_path} =
            _create_placeholder_item($segments[$i], $current_path);
        }
        # Move to the children level
        $current_level = $current_level->{$current_path}->{children};
      }
    }
  }

  sub _build_nav_level($parent_ul, $items_hash, $current_path, $parent_path) {
    # Sort items by order
    my @sorted_items =
      sort {
      $items_hash->{$a}->{order} <=> $items_hash->{$b}->{order}
        or fc($items_hash->{$a}->{title}) cmp fc($items_hash->{$b}->{title})
      }
      keys %$items_hash;

    for my $item_path (@sorted_items) {
      my $item      = $items_hash->{$item_path};
      my $full_path = $item->{path};

      # Determine states
      my $is_exact_match = ($current_path eq $full_path);
      my $is_on_path =
        ($current_path =~ /^\Q$full_path\E/);    # Current page OR ancestor

      # CSS classes for <li>
      my @li_classes = ('spectrum-TreeView-item');
      push @li_classes, 'is-selected' if $is_exact_match;
      push @li_classes, 'is-open'     if $is_on_path;

      my $li = HTML::Element->new('li', class => join(' ', @li_classes));

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
        my $should_be_opened = $is_on_path
          || _path_contains_current($item->{children}, $current_path,
          $full_path);

        # CSS classes for child <ul>
        my @ul_classes = ('spectrum-TreeView', 'spectrum-TreeView--sizeM');
        push @ul_classes, 'is-opened' if $should_be_opened;

        my $child_ul =
          HTML::Element->new('ul', class => join(' ', @ul_classes));
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

    my $raw_path = $item->{path};

    # Convert filesystem path to web path
    my $web_path = _filesystem_path_to_web_path($c, $raw_path);

    unless (!$rejected_items_by_path->{$web_path}) {
      $logger->debug("Skipping rejected path $web_path");
      return;
    }

    unless (exists $item->{title}) {
      $logger->error("Item rejected: missing title for $web_path");
      return;
    }

    $logger->debug(
      "NAVIGATION: Registering path '$web_path' with title '$item->{title}'");

    # Update the item to use the web path
    my $web_item = {%$item};    # Copy the item
    $web_item->{path} = $web_path;

    # Build the hierarchical structure using the web path
    _build_path_hierarchy($web_path, $web_item);

    return 1;
  }

  sub _titleize ($seg) {
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
