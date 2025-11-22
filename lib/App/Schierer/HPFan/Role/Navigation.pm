
package App::Schierer::HPFan::Role::Navigation;
  use Mojo::Base -role, -signatures;
  use v5.42.0;
  use utf8::all;
  use experimental qw(class);
  require Data::Printer;
  require HTML::Element;
  require Log::Log4perl;

  my %nav_items_by_path;
  my %raw_paths;

  my $rejected_items_by_path = {
    '/policy'         => 1,
    '/policy/privacy' => 1,
    '/index'          => 1,
  };

  sub add_navigation_item ($self, $item) {

    unless (ref $item eq 'HASH' && $item->{path}) {
      $self->logger->error(
        "Invalid item (missing path): " . Data::Printer::np($item));
      return;
    }

    my $raw_path = $item->{path};
    my $web_path = $self->_filesystem_path_to_web_path($raw_path);

    unless (!$rejected_items_by_path->{$web_path}) {
      $self->logger->debug("Skipping rejected path $web_path");
      return;
    }

    unless (exists $item->{title}) {
      $self->logger->error("Item rejected: missing title for $web_path");
      return;
    }

    $self->logger->debug(
      "NAVIGATION: Registering path '$web_path' with title '$item->{title}'");

    my $web_item = {%$item};
    $web_item->{path} = $web_path;

    $self->_build_path_hierarchy($web_path, $web_item);
    $self->logger->debug("Added to raw_paths: $web_path");

    return 1;
  }

  sub generate_navigation($self, $current_path = undef, $detached = 0) {
    $current_path //= $self->req->url->path->to_string;

    my $ul = HTML::Element->new(
      'ul',
      class => sprintf('spectrum-TreeView spectrum-TreeView--sizeM %s',
        $detached ? 'spectrum-TreeView--detached' : '')
    );

    $self->build_nav_level($ul, \%nav_items_by_path, $current_path, '');
    return $ul->as_HTML;
  }

  sub build_nav_level($self, $parent_ul, $items_hash, $current_path, $parent_path) {
    my @sorted_items =
      sort {
      $items_hash->{$a}->{order} <=> $items_hash->{$b}->{order}
        or fc($items_hash->{$a}->{title}) cmp fc($items_hash->{$b}->{title})
      }
      keys %$items_hash;

    for my $item_path (@sorted_items) {
      my $item      = $items_hash->{$item_path};
      my $full_path = $item->{path};

      my $is_exact_match = ($current_path eq $full_path);
      my $is_on_path = ($current_path =~ /^\Q$full_path\E/);

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

      if ($item->{children} && %{ $item->{children} }) {
        my $should_be_opened = $is_on_path
          || $self->_path_contains_current($item->{children}, $current_path,
          $full_path);

        my @ul_classes = ('spectrum-TreeView', 'spectrum-TreeView--sizeM');
        push @ul_classes, 'is-opened' if $should_be_opened;

        my $child_ul =
          HTML::Element->new('ul', class => join(' ', @ul_classes));
        $li->push_content($child_ul);
        $self->build_nav_level($child_ul, $item->{children}, $current_path,
          $full_path);
      }

      $parent_ul->push_content($li);
    }
  }

  sub get_existing_navigation_items ($self) {
    return \%raw_paths;
  }

  sub _filesystem_path_to_web_path($self, $file_path) {
    my $dist_dir = Mojo::Home->new->detect;
    my $web_path = $file_path;

    $web_path =~ s/^\Q$dist_dir\E\/pages//;
    $web_path =~ s/\/index\.md$//;
    $web_path =~ s/\.md$//;
    $web_path = '/' . $web_path unless $web_path =~ /^\//;
    $web_path = '/' if $web_path eq '';

    return $web_path;
  }

  sub _build_path_hierarchy($self, $path, $item) {

    my @segments      = grep { $_ ne '' } split '/', $path;
    my $current_level = \%nav_items_by_path;
    my $current_path  = '';

    for my $i (0 .. $#segments) {
      $current_path .= '/' . $segments[$i];

      if ($i == $#segments) {
        $self->_merge_or_add_item($current_level, $current_path, $item);
        $raw_paths{$current_path}++ unless $item->{'_is_placeholder'};
      }
      else {
        unless (exists $current_level->{$current_path}) {
          $current_level->{$current_path} =
            $self->_create_placeholder_item($segments[$i], $current_path);
        }
        if (exists $current_level->{$current_path}->{children}) {
          $current_level = $current_level->{$current_path}->{children};
        }
        else {
          $current_level->{$current_path}->{children} = {};
          $current_level = $current_level->{$current_path}->{children};
        }
      }
    }
  }

  sub _create_placeholder_item($self, $segment_name, $full_path) {
    return {
      title           => $self->_titleize($segment_name),
      path            => $full_path,
      order           => 9999,
      children        => {},
      _is_placeholder => 1
    };
  }

  sub _merge_or_add_item($self, $level, $path, $new_item) {

    if (exists $level->{$path}) {
      my $existing = $level->{$path};

      if ($existing->{_is_placeholder} && !$new_item->{_is_placeholder}) {
        if (exists $new_item->{children}) {
          foreach my $child (keys %{ $existing->{children} }) {
            $new_item->{children}->{$child} = $existing->{children}->{$child};
          }
        }
        else {
          $new_item->{children} = $existing->{children}
            if $existing->{children};
        }
        $level->{$path} = $new_item;
        $raw_paths{$path}++;
      }
      elsif (!$existing->{_is_placeholder} && !$new_item->{_is_placeholder}) {
        if (exists $new_item->{order} && exists $existing->{order}) {
          if ($new_item->{order} < $existing->{order}) {
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
    }
    else {
      $level->{$path} = $new_item;
      $raw_paths{$path}++;
    }
  }

  sub _path_contains_current($self, $children_hash, $current_path, $parent_path) {
    for my $child_path (keys %$children_hash) {
      my $full_child_path =
        $parent_path . $children_hash->{$child_path}->{path};

      if ($current_path =~ /^\Q$full_child_path\E/) {
        return 1;
      }
    }
    return 0;
  }

  sub _titleize ($self, $seg) {
    $seg =~ s/_/ /g;
    return join ' ', map { ucfirst lc } split ' ', $seg;
  }

1;
__END__
# ABSTRACT: Role providing navigation methods
