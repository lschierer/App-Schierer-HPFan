use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require HTML::Strip;

class App::Schierer::HPFan::View::Timeline
  : isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any min max firstidx );
  use Scalar::Util   qw(blessed);
  #something about this package requies that it be used not just required
  use SVG;
  use Readonly;
  use Math::Trig ':pi';
  use POSIX qw(ceil);
  use Carp;

  field $name : param //= 'Timeline';

  field $events : param //= [];

  # internal fields

  field $replacements     = {};
  field $categories       = {};
  field $nodes_by_sortval = {};

 # All of these are expected to be set at run time based on the live data.
 #default this to a very high number that should be bigger than my julian dates.
  field $min_date = 9**9;
  field $max_date = 0;
  field $ymax     = 5500;
  field $xmax     = 880;
  # vertial version of an FR unit for minimum node separation in the y axis
  field $vfr = 0;
# testing has demonstrated that the we want to scale vertically by several fractions.
# the logic of having a css style fractional unit seams sound, I don't want to change
# that, I just want to use N of them where N is the scaling factor.
  field $fr_scaling_factor = 2;
  ## for collision avoidance

  # hash at distance radius,
  # each containing an array of { x => $x, y => $y, radius => $r }
  field $used_positions = [];

  # these are constants
  field $detail_distance;
  field $detail_width;
  field $detail_height = 0;
  field $detail_radius;

  # output fields
  field $graph : reader;
  field $edges_group;
  field $nodes_group;
  field $text_group;
  field $category_groups = {};

  method viewheight {
    max($ymax * ($fr_scaling_factor + 0.6), $ymax + $detail_height,);
  }

  ADJUST {
    #  # only the angles that fit in the layout

    Readonly::Scalar my $stw => 120;
    $detail_width = $stw;

    #  # base distance from timeline dot
    Readonly::Scalar my $st1 => $detail_width * 3 / 4;
    $detail_distance = $st1;

    # ensure we have room for 7 ranks horizontally
    # 100 for the categories
    # 100 for the gaps.
    $xmax = $detail_width * 6 + 200;

    Readonly::Scalar my $sth =>
      int(($self->viewheight / (scalar($events->@*) * 4)));
    $detail_height = $sth;
    $self->logger->info(sprintf(
      'based on %s events and %s viewheight, detail_height is %s',
      scalar($events->@*), $self->viewheight, $detail_height
    ));

    #  # space each detail needs
    Readonly::Scalar my $st2 => max($detail_width, $detail_height) / 2;
    $detail_radius = $st2;

    # because I have the 'fr' unit minimum distance factor, I have found that
    # the view box has to be bigger than the computed ymax node pre-application
    # of the fr unit.

    $graph = SVG->new(
      preserveAspectRatio => 'xMidYMid meet',    # how to scale
    );
    $edges_group =
      $graph->group(id => 'layer-edges', class => 'timeline edges');
    $nodes_group =
      $graph->group(id => 'layer-nodes', class => 'timeline nodes');
    $text_group = $graph->group(id => 'layer-text', class => 'timeline text');

  }

  method create {
    $self->_organize_events_by_category_and_date();
    $self->_create_detail_nodes_and_connections();

    return $self->_process_svg_output();
  }

  method get_category_for_event( $event ) {
    my $category = $event->event_class // 'generic';
    my @parts    = grep {length} split /\s+/, ($event->event_class // '');
    if (scalar @parts) {
      @parts = grep { $_ !~ /mundane/i } @parts;
      if (scalar @parts) {
        @parts    = sort @parts;
        $category = 'generic';
        if ($parts[0] =~ /england/i) {
          if ($#parts >= 1 && $parts[1] =~ /scotland/i) {
            $category = 'gb';
          }
        }
        if ($category eq 'generic' && scalar(@parts)) {
          $category = join(' ', @parts);
        }
      }
    }
    return $category;
  }

  method _organize_events_by_category_and_date {
    foreach my $event ($events->@*) {
      unless (Scalar::Util::reftype($event) eq 'OBJECT'
        && $event->isa('App::Schierer::HPFan::Model::History::Event')) {
        $self->logger->warn(sprintf('Skipping invalid event: %s', ref($event)));
        next;
      }

      my $category = $self->get_category_for_event($event);
      $self->logger->debug(sprintf('computed category %s from event id %s cat string %s.',
      $category, $event->id, $event->event_class));

      my $date = $event->sortval;
      # set the base y cordinate to the minimum Julian Date
      $min_date = min($min_date, $event->sortval);
      $max_date = max($max_date, $event->sortval);

      push @{ $categories->{$category}->{$date} }, $event;
    }
    foreach my $category (keys $categories->%*) {
      my $layer_name = $category =~ s/ /-/r;
      $layer_name = "${layer_name}-layer";
      $self->logger->debug(
        "layer for category '$category' layer name '$layer_name'");

      $category_groups->{$category} =
        $nodes_group->group(
          id => "$layer_name",
          class => "timeline nodes ${category}");
    }
    $vfr = $ymax / scalar @$events;    # fractional unit based on event count
    $self->logger->debug("vfr is $vfr");
  }

  method _create_detail_nodes_and_connections {
    my @sortedEvents = sort {
      my $svc = $a->sortval <=> $b->sortval;
      if($svc == 0) {
        return $a->date cmp $b->date
      } return $svc;
    } grep {
      Scalar::Util::reftype($_) eq 'OBJECT'
      && $_->isa('App::Schierer::HPFan::Model::History::Event')
    } $events->@*;

    my $previous_pos;
    foreach my $event (@sortedEvents) {
      my $category = $self->get_category_for_event($event);
      my $sv = $event->sortval;
      my $dot_node_name = "dot_${category}_${sv}";
      my $pos;
      if(! exists $nodes_by_sortval->{$sv}->{$dot_node_name}) {
        $pos = $self->_get_normalized_position($category, $sv);
        # y cordinates go down from upper left corner
        # 3 is the minumum spot at which we can draw a node circle.
        my $miny =
          defined($previous_pos->{$category})
          ? $previous_pos->{$category}->{y} + $vfr * $fr_scaling_factor
          : 3;
        if ($miny > $pos->{y}) {
          my $dy = $miny - $pos->{y};
          $ymax = $ymax + $dy;
          $pos->{y} = $miny;
        }

        my $nc = $category_groups->{$category}->circle(
          cx    => $pos->{x},
          cy    => $pos->{y},
          r     => 3,
          class => "node timeline $category",
          id    => "dot_${category}_${sv}",
        );

        if (defined $previous_pos->{$category}) {
          my $prev = $previous_pos->{$category};
          $edges_group->line(
            x1    => $pos->{x},
            y1    => $prev->{y} + 3,
            x2    => $pos->{x},
            y2    => $pos->{y} - 3,
            class => "timeline edge $category",
          );
        }

        $previous_pos->{$category} = $pos;
        $nodes_by_sortval->{$sv}->{$dot_node_name} = $pos;
      }
      # if we by-pass the if block, we need to know the $pos value
      $pos = $nodes_by_sortval->{$sv}->{$dot_node_name};

      my $detail_pos = $self->_find_detail_position($event, $pos);
      # Draw dashed line from timeline dot to detail box
      # Draw the line to the corner, not the center.
      $edges_group->line(
        x1    => $pos->{x},
        y1    => $pos->{y},
        x2    => $detail_pos->{x} - $detail_pos->{width} / 2,
        y2    => $detail_pos->{y} - $detail_pos->{height} / 2,
        class => "timeline detail-edge $category",
      );
      $self->_create_detail_node_for_event($event, $detail_pos);

    }
    $self->logger->trace("svg is currently " . $graph->xmlify);
  }

  # event is undefined if it is a timeline dot node
  method _get_normalized_position($category, $julian, $event = undef) {
    my @catNames = keys $categories->%*;
    my $catIndex = firstidx { $_ eq $category } @catNames;

    my $xcord = 10 * ($catIndex + 1);

    if (defined($event)) {
      # Detail node spreading logic
      my @events_on_date = @{ $categories->{$category}->{ $event->sortval } };
      my $event_index    = firstidx { $_->id eq $event->id } @events_on_date;
      my $num_events     = @events_on_date;

      my $detail_start = $xcord + 50;
      my $separation   = 100 / $num_events;

      if ($num_events == 1) {
        $xcord = int($detail_start + $separation);
      }
      else {
        $xcord =
          int($detail_start + abs((rand($event_index + 1) * $separation)));
      }
    }

    my $date_span = $max_date - $min_date;
    # INVERT: Subtract from max to flip the timeline
    my $normalized_y = ($julian - $min_date) / ($max_date - $min_date) * $ymax;
    return {
      x => int($xcord),
      y => int($normalized_y),
    };
  }

  method _calc_height($event, $wide = 0) {
    my $line_height              = 13;
    my $chars_per_line           = 30;
    my $date_chars_per_line      = 23;
    my $wide_chars_per_line      = 40;
    my $wide_date_chars_per_line = 33;
    my $hs                       = HTML::Strip->new();
    my $lines                    = 2;    # date + (blurb OR description) minimum

    my $tc = $wide ? $wide_chars_per_line : $chars_per_line;
    if (length($event->blurb) > $tc) {
      # subtract one for the line already allocated
      my $bl = ceil((length($event->blurb) / $tc) - 1);
      $self->logger->debug("blurb adding $bl to lines for " . $event->id);
      $lines += $bl unless ($bl < 0);
    }

    # date uses slightly larger text
    my $dc = $wide ? $wide_date_chars_per_line : $date_chars_per_line;
    if (length($event->date->to_string) > $dc) {
      # subtract one for the line already allocated
      my $dl = ceil((length($event->date->to_string) / $dc) - 1);
      $self->logger->debug("date adding $dl to lines for " . $event->id);
      $lines += $dl unless ($dl < 0);
    }

    # Count extra lines from content
    if (defined($event->description)
      && length($event->description)) {
      my $text_only = $hs->parse($event->description);

      my $dl = ceil((length($text_only) / $tc));
      $self->logger->debug("description adding $dl to lines for " . $event->id);
      $lines += $dl unless ($dl < 0);
    }

    my $sl = scalar @{ $event->sources };
    $self->logger->debug("sources adding $sl to lines for " . $event->id);
    $lines += $sl unless ($sl < 0);

    my $height = max($detail_height, ($lines * $line_height));
    return $height;

  }

  method _calculate_detail_dimensions($event) {
    my $hs     = HTML::Strip->new();
    my $width  = $detail_width;
    my $height = $detail_height;

    # Maybe wider boxes for long descriptions to reduce wrapping
    if ($event->description && length($hs->parse($event->description)) > 50) {
      $width += 40;
      $height = $self->_calc_height($event, 1);
    }
    else {
      $height = $self->_calc_height($event);
    }

    return { width => $width, height => $height };
  }

  method _create_detail_node_for_event ($event, $pos) {
    my $height = $pos->{height} // $detail_height;
    my $width  = $pos->{width}  // $detail_width;
    if (not defined($pos->{height}) or $pos->{height} < 3) {
      $self->dev_guard(sprintf(
        'detail node with no height for event %s: %s',
        $event->id, Data::Printer::np($pos, multiline => 0)
      ));
    }

    # 1) Split event_class into tokens (whitespace-separated)
    my @parts = grep {length} split /\s+/, ($event->event_class // '');

    # “whitespace count + 1” stops; ensure at least 1 stop
    my $n_stops = @parts ? (@parts + 1) : 1;

    # 2) Build style that maps tokens to --stop-i using your CSS palette vars
    # e.g. "--stop-1: var(--england); --stop-2: var(--scotland); ..."
    my $style = join '; ',
      map { my $i = $_ + 1; "--stop-$i: var(--$parts[$_])" } (0 .. $#parts);

    (my $safe_id = $event->id // 'evt') =~ s/[^A-Za-z0-9_.:-]+/_/g;
    my $grad_id = "grad_$safe_id";

    my $group = $text_group->tag(
      'g',
      x      => $pos->{x} - $width / 2,
      y      => $pos->{y} - $height / 2,
      width  => $width,
      height => $height,
      id     => $event->id,
      class  => sprintf('timeline node %s', $event->event_class),
      (length $style ? (style => $style) : ()),
    );

    my $defs = $group->tag('defs');
    my $lg   = $defs->tag(
      'linearGradient',
      id                => $grad_id,
      x1                => '0%',
      y1                => '0%',
      x2                => '100%',
      y2                => '0%',
      gradientUnits     => 'objectBoundingBox',
      gradientTransform => 'rotate(175)'          # adjust angle as you like
    );

    # Build evenly spaced stops. Each stop uses --stop-i with fallbacks.
    for my $i (1 .. $n_stops) {
      my $offset =
        ($n_stops == 1)
        ? '15%'
        : sprintf('%.3f%%', ($i - 1) * 100 / ($n_stops - 1));

      $lg->tag(
        'stop',
        offset       => $offset,
        'stop-color' => "var(--stop-$i, var(--category-color, currentColor))",
      );
    }

    # a rectangle creates from the top left corner.
    $group->rectangle(
      x      => $pos->{x} - $width / 2,
      y      => $pos->{y} - $height / 2,
      width  => $width,
      height => $height,
      rx     => 0.1,
      ry     => 0.1,
      (scalar @parts ? (fill => "url(#$grad_id)",) : ()),
    );

    my $fo = $group->foreignObject(
      x      => $pos->{x} - $width / 2,
      y      => $pos->{y} - $height / 2,
      width  => $width,
      height => $height,
    );

    $fo->comment(sprintf('event %s sortval %s', $event->id, $event->sortval));

    my $div = $fo->tag(
      'div',
      id    => sprintf('fo-div-%s', $event->id),
      xmlns => 'http://www.w3.org/1999/xhtml',
      class => sprintf('timeline node-label %s', $event->event_class),
    );

    $div->tag('div',
      class => 'spectrum-Heading spectrum-Heading--sizeM '
        . 'spectrum-Heading--serif spectrum-Heading--strong')
      ->cdata($event->date->to_string);

    if (defined($event->blurb) && length($event->blurb)) {
      $div->tag('div',
        class =>
          'spectrum-Heading spectrum-Heading--sizeS spectrum-Heading--serif')
        ->cdata($event->blurb);
    }

    if (defined($event->description) && length($event->description)) {
      $self->logger->debug(sprintf(
        'adding description "%s" to event %s',
        $event->description, $event->id
      ));

      my $cc = $div->tag('div',
        class => 'spectrum-Body spectrum-Body--sizeS spectrum-Body--serif');
      $cc->cdata_noxmlesc($event->description);
    }

    foreach my $source ($event->sources->@*) {
      $div->tag('div',
        class => 'spectrum-Body spectrum-Body--sizeS spectrum-Body--serif')
        ->cdata($source);
    }
  }

  method _process_svg_output {

    my $svg = $graph->xmlify(
      -pubid  => "-//W3C//DTD SVG 1.0//EN",
      -inline => 1
    );
    my $viewbox = sprintf('0 0 %s %s', $xmax, $self->viewheight);
    # Your existing SVG cleanup
    $svg =~ s/<svg /<svg viewBox="$viewbox"/;

    $svg =~
s/<text ([^>]+) font-family="[^"]+" font-size="[^"]+">/<text $1 class="spectrum-Heading spectrum-Heading--size-M spectrum-Heading--serif">/g;

    return $svg;
  }

  ##### positioning for details

  method _find_detail_position($event, $timeline_pos) {
    # Simple approach: try positions in a predictable spiral pattern
    my $size = $self->_calculate_detail_dimensions($event);
    my @try_positions;

    my $gutter = 3;
    for (my $i = 0; $i < 15; $i++) {
      push @try_positions,
        {
        x        => $timeline_pos->{x} + $size->{width} * $i,
        y        => $timeline_pos->{y},
        distance => 350
        };

      push @try_positions,
        {
        x => $size->{width} * $i,
        y => $size->{height} * $i,
        };
      push @try_positions,
        {
        x => $size->{width} + $timeline_pos->{x},
        y => $size->{height} * $i + 10,
        };

      push @try_positions,
        {
        x => $size->{width} * $i + 10,
        y => $size->{height} + $timeline_pos->{y},
        };

      push @try_positions,
        {
        x => $size->{width} * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} + $size->{height} * $i,
        };

      push @try_positions,
        {
        x => $size->{width} + $timeline_pos->{x},
        y => $timeline_pos->{y} + $size->{height} * $i,
        };

      push @try_positions, {
        x => $size->{width} * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} - $size->{height} * $i,    # negative Y
      };

      push @try_positions,
        {
        x => $size->{width} * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} - $size->{height} * $i,
        };

      push @try_positions,
        {
        x => $timeline_pos->{x} + $size->{width} * $i + ($size->{width} / 2),
        y => $timeline_pos->{y},
        };

      push @try_positions,
        {
        x => $timeline_pos->{x} - $size->{width} * $i + ($size->{width} / 2),
        y => $timeline_pos->{y},
        };

      push @try_positions,
        {
        x => $timeline_pos->{x} - $size->{width} * $i,
        y => $timeline_pos->{y} - $size->{height} * $i * 2,
        };

      push @try_positions,
        {
        x => $timeline_pos->{x} + $size->{width} * int($i / 2),
        y => $timeline_pos->{y} - $size->{height} * 3 * $i,
        };

    }

    # Sort by distance from timeline position (closest first)
    @try_positions = sort {
      my $dist_a = sqrt(
        ($a->{x} - $timeline_pos->{x})**2 + ($a->{y} - $timeline_pos->{y})**2);
      my $dist_b = sqrt(
        ($b->{x} - $timeline_pos->{x})**2 + ($b->{y} - $timeline_pos->{y})**2);
      $dist_a <=> $dist_b;
    } @try_positions;

    foreach my $pos (@try_positions) {
      if ($self->_is_position_clear($event, $size, $pos)) {
        $self->logger->debug(sprintf(
          '%s recieved true for pos %s %s',
          $event->id, $pos->{x}, $pos->{y}
        ));
        # store the amount of space we used as well as the center of that space
        $pos->{width}  = $size->{width};
        $pos->{height} = $size->{height};
        push @{$used_positions}, $pos;
        return $pos;
      }
    }

    # Fallback
    my $fb = {
      x      => $timeline_pos->{x} + 400,
      y      => $timeline_pos->{y} + 10,
      width  => $size->{width},
      height => $size->{height},
    };
    push @{$used_positions}, $fb;
    $self->logger->warn(sprintf(
      'using fallback value for event %s: pos %s %s',
      $event->id, $fb->{x}, $fb->{y}
    ));
    return $fb;
  }

  method _is_position_clear($event, $size, $pos) {
    my $PAD = 2;

    return 0 unless $pos->{y} >= 0;
    return 0 unless $pos->{x} >= 1;

    # Convert center to corner for boundary checking
    my $corner_x = $pos->{x} - $size->{width} / 2;
    my $corner_y = $pos->{y} - $size->{height} / 2;

    # Boundary checks using corner coordinates
    my @catNames   = keys $categories->%*;
    my $numCats    = scalar @catNames;
    my $leftGutter = ($numCats + 1) * 10;

    return 0 if $corner_x <= $leftGutter + $PAD;
    return 0 if $corner_x + $size->{width} >= $xmax - $PAD;
    return 0 if $corner_y < 3 + $PAD;
    return 0 if $corner_y + $size->{height} >= $ymax + $detail_height - $PAD;

    # Collision detection using CENTER coordinates
    foreach my $used ($used_positions->@*) {
      if ($pos->{x} == $used->{x} && $pos->{y} == $used->{y}) {
        return 0;    # exact match
      }

      # Center-to-center collision detection
      my $x_distance = abs($pos->{x} - $used->{x});
      my $y_distance = abs($pos->{y} - $used->{y});

      # Require at least PAD px extra beyond just touching
      my $min_x_distance = ($size->{width} + $used->{width}) / 2 + $PAD;
      my $min_y_distance = ($size->{height} + $used->{height}) / 2 + $PAD;

      if ($x_distance <= $min_x_distance && $y_distance <= $min_y_distance) {
        return 0;    # overlap detected
      }

    }
    $self->logger->debug(sprintf(
      'no test case failed for event %s with pos %s %s',
      $event->id, $pos->{x}, $pos->{y}
    ));
    return 1;    # position is clear
  }

}
1;
__END__
