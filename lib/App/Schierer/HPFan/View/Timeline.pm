use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require Pandoc;

class App::Schierer::HPFan::View::Timeline
  : isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any min max firstidx );
  use Scalar::Util   qw(blessed);
  #something about this package requies that it be used not just required
  use SVG;
  use Readonly;
  use Math::Trig ':pi';
  use Carp;

  field $name : param //= 'Timeline';

  field $events : param //= [];

  # internal fields

  # pandoc for future use
  field $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );
  field $parser = Pandoc->new();

  field $categories       = {};
  field $nodes_by_sortval = {};
  field $category_offset  = {};

  field $base_x = 10;    # I decided 100 was too much separation

 # All of these are expected to be set at run time based on the live data.
 #default this to a very high number that should be bigger than my julian dates.
  field $base_y   = 9**9;
  field $min_date = 9**9;
  field $max_date = 0;
  field $ymax     = 6500;
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
  field $angles;
  field $detail_distance;
  field $detail_width;
  field $detail_height;
  field $detail_radius;

  ADJUST {

  }

  # output fields
  field $graph : reader;

  field $viewheight;

  ADJUST {
    #  # only the angles that fit in the layout
    Readonly::Hash my %tmp => {
      0     => 1,    # most preferred
      22.5  => 2,
      -22.5 => 3,
      45    => 4,
      -45   => 5,    # least preferred
    };
    $angles = \%tmp;

    Readonly::Scalar my $stw => 120;
    $detail_width = $stw;

    Readonly::Scalar my $sth => 80;
    $detail_height = $sth;

    #  # base distance from timeline dot
    Readonly::Scalar my $st1 => $detail_width * 3 / 4;
    $detail_distance = $st1;

    # ensure we have room for 7 ranks horizontally
    # 100 for the categories
    # 100 for the gaps.
    $xmax       = $detail_width * 6 + 200;
    $viewheight = $ymax * ($fr_scaling_factor + 0.6);
    #  # for collision detection

    #  # space each detail needs
    Readonly::Scalar my $st2 => max($detail_width, $detail_height) / 2;
    $detail_radius = $st2;

    # because I have the 'fr' unit minimum distance factor, I have found that
    # the view box has to be bigger than the computed ymax node pre-application
    # of the fr unit.

    $graph = SVG->new(
      viewBox => "0 0 $xmax $viewheight",        # defines coordinate system
      preserveAspectRatio => 'xMidYMid meet',    # how to scale
    );
  }

  # Convert degrees to radians for the lookup
  method _get_angle_preference($angle_rad) {
    my $angle_deg = $angle_rad * (180 / Math::Trig::pi);
    return $angles->{$angle_deg} // 999;    # default to very low preference
  }

  method create {
    $self->_organize_events_by_category_and_date();
    $self->_create_detail_nodes_and_connections();

    return $self->_process_svg_output();
  }

  method _organize_events_by_category_and_date {
    foreach my $event ($events->@*) {
      unless (Scalar::Util::reftype($event) eq 'OBJECT'
        && $event->isa('App::Schierer::HPFan::Model::History::Event')) {
        $self->logger->warn(sprintf('Skipping invalid event: %s', ref($event)));
        next;
      }

      my $category = $event->event_class // 'generic';
      my $date     = $event->sortval;
      # set the base y cordinate to the minimum Julian Date
      $base_y   = min($base_y,   $event->sortval);
      $min_date = min($min_date, $event->sortval);
      $max_date = max($max_date, $event->sortval);

      push @{ $categories->{$category}->{$date} }, $event;
    }
    $vfr = $ymax / scalar @$events;    # fractional unit based on event count
    $self->logger->debug("vfr is $vfr");
  }

  method _create_detail_nodes_and_connections {
    my @catNames = keys $categories->%*;
    foreach my $index (0 .. $#catNames) {
      my $category = $catNames[$index];

      my $previous_pos;
      foreach my $date (sort keys $categories->{$category}->%*) {
   # events will collide on dates, so assume that we might have already created
   # a given node perhaps because of the birthday paradox (amoung other reasons)
        my $dot_node_name = "dot_${category}_${date}";
        next if exists $nodes_by_sortval->{$date}->{$dot_node_name};
        $nodes_by_sortval->{$date}->{$dot_node_name} = 1;

        my @events_on_date = @{ $categories->{$category}->{$date} };
        my $pos            = $self->_get_normalized_position($category, $date);

        # y cordinates go down from upper left corner
        # 3 is the minumum spot at which we can draw a node circle.
        my $miny =
          defined($previous_pos)
          ? $previous_pos->{y} + $vfr * $fr_scaling_factor
          : 3;
        $pos->{y} = max($pos->{y}, $miny);
        my $nc = $graph->circle(
          cx    => $pos->{x},
          cy    => $pos->{y},
          r     => 3,
          class => "node timeline $category",
          id    => "dot_${category}_${date}",
        );

        if (defined $previous_pos) {
          $graph->line(
            x1    => $pos->{x},
            y1    => $previous_pos->{y} + 3,
            x2    => $pos->{x},
            y2    => $pos->{y} - 3,
            class => "timeline edge $category",
          );
        }

        $previous_pos = $pos;
        my $detail_distance = 50;    # pixels from timeline dot

        foreach my $i (0 .. $#events_on_date) {
          my $event      = $events_on_date[$i];
          my $detail_pos = $self->_find_detail_position($event, $pos);
          # Draw dashed line from timeline dot to detail box
          # Draw the line to the corner, not the center.
          $graph->line(
            x1    => $pos->{x},
            y1    => $pos->{y},
            x2    => $detail_pos->{x} - $detail_width / 2,
            y2    => $detail_pos->{y} - $detail_height / 2,
            class => "timeline detail-edge $category",
          );
          $self->_create_detail_node_for_event($event, $detail_pos);
        }
      }
      $self->logger->debug("svg is currently " . $graph->xmlify);
    }
  }

  method _calculate_detail_dimensions($event) {
    my $base_width     = 80;
    my $base_height    = 40;
    my $line_height    = 12;
    my $chars_per_line = 15;    # rough estimate for your font size

    my $lines = 2;              # date + (blurb OR description) minimum

    # Count extra lines from content
    if ( defined($event->blurb)
      && defined($event->description)
      && length($event->blurb)
      && length($event->description)) {
      $lines++;    # both blurb AND description
    }

    # Estimate wrapped lines for description
    if ($event->description && length($event->description) > $chars_per_line) {
      my $desc_lines = int(length($event->description) / $chars_per_line) + 1;
      $lines += ($desc_lines - 1)
        ;          # subtract 1 since we already counted the description line
    }

    $lines += scalar @{ $event->sources };

    my $width  = $base_width;
    my $height = $base_height + (($lines - 2) * $line_height);

    # Maybe wider boxes for long descriptions to reduce wrapping
    if ($event->description && length($event->description) > 50) {
      $width += 40;
      # Recalculate lines with wider box
      my $wider_chars_per_line = 25;
      if (length($event->description) > $wider_chars_per_line) {
        my $desc_lines =
          int(length($event->description) / $wider_chars_per_line) + 1;
        $lines =
          $lines -
          int(length($event->description) / $chars_per_line) +
          $desc_lines - 1;
        $height = $base_height + (($lines - 2) * $line_height);
      }
    }

    return { width => $width, height => $height };
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

  method _create_detail_node_for_event ($event, $pos) {

    $graph->circle(
      stroke         => 'blue',
      fill           => 'solid',
      'stroke-width' => 3,
      cx             => $pos->{x},
      cy             => $pos->{y},
      r              => 3,
    );

    my $group = $graph->tag(
      'g',
      x      => $pos->{x} - $detail_width / 2,
      y      => $pos->{y} - $detail_height / 2,
      width  => $detail_width,
      height => $detail_height,
      id     => $event->id,
      class  => sprintf('timeline node %s', $event->event_class),
    );
    # a rectangle creates from the top left corner.
    $group->rectangle(
      x      => $pos->{x} - $detail_width / 2,
      y      => $pos->{y} - $detail_height / 2,
      width  => $detail_width,
      height => $detail_height,
      rx     => 0.1,
      ry     => 0.1,
    );

    my $fo = $group->foreignObject(
      x      => $pos->{x} - $detail_width / 2,
      y      => $pos->{y} - $detail_height / 2,
      width  => $detail_width,
      height => $detail_height
    );

    my $div = $fo->tag(
      'div',
      xmlns => 'http://www.w3.org/1999/xhtml',
      class => sprintf('timeline node-label %s', $event->event_class),
    );

    $div->tag('div',
      class => 'spectrum-Heading spectrum-Heading--sizeM '
        . 'spectrum-Heading--serif spectrum-Heading--strong')
      ->cdata($event->print_date);

    if (defined($event->blurb) && length($event->blurb)) {
      $div->tag('div',
        class =>
          'spectrum-Heading spectrum-Heading--sizeS spectrum-Heading--serif')
        ->cdata($event->blurb);
    }

    if (defined($event->description) && length($event->description)) {
      $div->tag('div',
        class => 'spectrum-Body spectrum-Body--sizeS spectrum-Body--serif')
        ->cdata($event->description);
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
    # Your existing SVG cleanup
    $svg =~
s/<text ([^>]+) font-family="[^"]+" font-size="[^"]+">/<text $1 class="spectrum-Heading spectrum-Heading--size-M spectrum-Heading--serif">/g;
    return $svg;
  }

  ##### positioning for details

  method _find_detail_position($event, $timeline_pos) {
    # Simple approach: try positions in a predictable spiral pattern
    my @try_positions;

    for (my $i = 0; $i < 15; $i++) {
      push @try_positions,
        {
        x        => $timeline_pos->{x} + $detail_width * $i,
        y        => $timeline_pos->{y},
        distance => 350
        };

      push @try_positions,
        {
        x => $detail_width * $i + 10,
        y => $detail_height * $i + 10,
        };
      push @try_positions,
        {
        x => $detail_width + $timeline_pos->{x},
        y => $detail_height * $i + 10,
        };

      push @try_positions,
        {
        x => $detail_width * $i + 10,
        y => $detail_height + $timeline_pos->{y},
        };

      push @try_positions,
        {
        x => $detail_width * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} + $detail_height * $i,
        };

      push @try_positions,
        {
        x => $detail_width + $timeline_pos->{x},
        y => $timeline_pos->{y} + $detail_height * $i,
        };

      push @try_positions, {
        x => $detail_width * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} - $detail_height * $i,    # negative Y
      };

      push @try_positions,
        {
        x => $detail_width * $i + $timeline_pos->{x},
        y => $timeline_pos->{y} - $detail_height * $i,
        };

      push @try_positions,
        {
        x => $timeline_pos->{x} + $detail_width * $i + ($detail_width / 2),
        y => $timeline_pos->{y},
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
      if ($self->_is_position_clear($event, $pos)) {
        $self->logger->debug(
          sprintf(
            '%s recieved true for pos %s %s',
            $event->id, $pos->{x}, $pos->{y}
          )
        );

        push @{$used_positions}, $pos;
        return { x => int($pos->{x}), y => int($pos->{y}) };
      }
    }

    # Fallback
    my $fb = { x => $timeline_pos->{x} + 400, y => $timeline_pos->{y} + 10 };
    $self->logger->warn(
      sprintf(
        'using fallback value for event %s: pos %s %s',
        $event->id, $fb->{x}, $fb->{y}
      )
    );
    return $fb;
  }

  method _is_position_clear($event, $pos) {
      return 0 unless $pos->{y} >= 0;
      return 0 unless $pos->{x} >= 1;

      # Convert center to corner for boundary checking
      my $corner_x = $pos->{x} - $detail_width/2;
      my $corner_y = $pos->{y} - $detail_height/2;

      # Boundary checks using corner coordinates
      my @catNames = keys $categories->%*;
      my $numCats = scalar @catNames;
      my $leftGutter = ($numCats + 1) * 10;

      return 0 if $corner_x <= $leftGutter;
      return 0 if $corner_x + $detail_width >= $xmax;
      return 0 if $corner_y < 3;
      return 0 if $corner_y + $detail_height > $viewheight;

      # Collision detection using CENTER coordinates
      foreach my $used ($used_positions->@*) {
          if ($pos->{x} == $used->{x} && $pos->{y} == $used->{y}) {
              return 0;  # exact match
          }

          # Center-to-center collision detection
          my $x_distance = abs($pos->{x} - $used->{x});
          my $y_distance = abs($pos->{y} - $used->{y});

          # Boxes overlap if center distance < box dimension
          if ($x_distance < $detail_width && $y_distance < $detail_height) {
              return 0;  # overlap detected
          }
      }
      $self->logger->debug(sprintf('no test case failed for event %s with pos %s %s', $event->id, $pos->{x}, $pos->{y}));
      return 1;  # position is clear
  }


}
1;
__END__
