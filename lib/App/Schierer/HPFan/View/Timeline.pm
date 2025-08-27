use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require HTML::Strip;
require App::Schierer::HPFan::View::Timeline::PositionHelpers;

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
  use App::Schierer::HPFan::View::Timeline::Utilities
    qw(get_category_for_event);

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
  field $ymax     = 10000;
  field $xmax     = 880;
  # vertial version of an FR unit for minimum node separation in the y axis
  field $vfr = 0;
# testing has demonstrated that the we want to scale vertically by several fractions.
# the logic of having a css style fractional unit seams sound, I don't want to change
# that, I just want to use N of them where N is the scaling factor.
  field $fr_scaling_factor = 2.5;
  ## for collision avoidance

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

  field $footnotes : reader = {};

  field $rails = {};

  field $ph = App::Schierer::HPFan::View::Timeline::PositionHelpers->new(
    detail_width  => $detail_width,
    detail_height => $detail_height,
  );

  method viewheight {
    min($ymax * ($fr_scaling_factor + 0.6), $ymax + $detail_height,);
  }

  ADJUST {
    #  # only the angles that fit in the layout

    Readonly::Scalar my $stw => 200;
    $detail_width = $stw;
    $ph->set_detail_width($detail_width);

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
    $ph->set_props(
      detail_width  => $detail_width,
      detail_height => $detail_height,
      categories    => $categories,
      min_date      => $min_date,
      max_date      => $max_date,
      ymax          => $ymax,
      xmax          => $xmax,
    );
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
    $ph->set_events($events);
    $self->_create_detail_nodes_and_connections();
    $ph->relaxer;
    $self->_draw_all_detail_boxes_from_boxes();

    return $self->_process_svg_output();
  }

  method _draw_all_detail_boxes_from_boxes {
    for my $cat (sort keys $ph->boxes->%*) {
      my $lane = $ph->boxes->{$cat};

      for my $pos (@$lane) {
        my $id = $pos->{id};
        if (not defined($id)) {
          $self->logger->error(
            'no id in pos: ' . Data::Printer::np($pos, multiline => 0));
          next;
        }
        my $event = $ph->event_by_id->{$id};
        unless ($event) {
          $self->logger->warn("No event found for id=$id; skipping draw");
          next;
        }
        my $category      = $pos->{category};
        my $sv            = $event->sortval;
        my $dot_node_name = "dot_${category}_${sv}";
        my $rail_node     = $rails->{$category}->{$dot_node_name};
        $self->logger->debug(sprintf(
          'rail node %s %s is %s',
          $category, $sv, Data::Printer::np($rail_node, multiline => 0)
        ));
        if (not defined $rail_node, or not defined $rail_node->{x}) {
          $self->logger->error(sprintf(
            'rail node for %s %s is missing or invalid: %s',
            $category, $sv, Data::Printer::np($rail_node, multiline => 0)
          ));
          next;
        }

        # draw the box content
        $self->_create_detail_node_for_event($event, $pos, $rail_node);
      }
    }
  }

  method _organize_events_by_category_and_date {
    foreach my $event ($events->@*) {
      unless (Scalar::Util::reftype($event) eq 'OBJECT'
        && $event->isa('App::Schierer::HPFan::Model::History::Event')) {
        $self->logger->warn(sprintf('Skipping invalid event: %s', ref($event)));
        next;
      }
      $self->logger->debug(sprintf('categorizing event %s.', $event->id));

      if (defined($event->sources) && scalar(@{ $event->sources })) {
        push @{ $footnotes->{ $event->id } }, $event->sources->@*;
      }

      my $category = get_category_for_event($self, $event, $self->logger);
      $self->logger->debug(sprintf(
        'computed category %s from event id %s cat string %s.',
        $category, $event->id, $event->event_class
      ));

      my $date = $event->sortval;
      # set the base y cordinate to the minimum Julian Date
      $min_date = min($min_date, $event->sortval);
      $max_date = max($max_date, $event->sortval);

      push @{ $categories->{$category}->{$date} }, $event;
    }
    foreach my $category (sort keys $categories->%*) {
      my $layer_name = $category =~ s/ /-/r;
      $layer_name = "${layer_name}-layer";
      $self->logger->debug(
        "layer for category '$category' layer name '$layer_name'");

      $category_groups->{$category} = $nodes_group->group(
        id    => "$layer_name",
        class => "timeline nodes ${category}"
      );
    }
    $vfr = $ymax / scalar @$events;    # fractional unit based on event count
    $self->logger->debug("vfr is $vfr");
  }

  method _create_detail_nodes_and_connections {
    my @sortedEvents = sort {
      my $svc = $a->sortval <=> $b->sortval;
      if ($svc == 0) {
        return $a->date cmp $b->date;
      }
      return $svc;
    } grep {
      Scalar::Util::reftype($_) eq 'OBJECT'
        && $_->isa('App::Schierer::HPFan::Model::History::Event')
    } $events->@*;

    my $previous_pos;
    foreach my $event (@sortedEvents) {
      my $category      = get_category_for_event($self, $event, $self->logger);
      my $sv            = $event->sortval;
      my $dot_node_name = "dot_${category}_${sv}";
      my $pos;
      if (!exists $nodes_by_sortval->{$sv}->{$dot_node_name}) {
        $ph->set_props(
          detail_width  => $detail_width,
          detail_height => $detail_height,
          categories    => $categories,
          min_date      => $min_date,
          max_date      => $max_date,
          ymax          => $ymax,
          xmax          => $xmax,
        );
        $pos = $ph->_get_normalized_position($ymax, $category, $sv);
        # y cordinates go down from upper left corner
        # 3 is the minumum spot at which we can draw a node circle.
        my $miny =
          defined($previous_pos->{$category})
          ? int($previous_pos->{$category}->{y} + $vfr * $fr_scaling_factor)
          : 3;
        if ($miny > $pos->{y}) {
          my $dy = $miny - $pos->{y};
          $ymax = $ymax + $dy;
          $pos->{y} = $miny;
        }

        my $lane_group = $category_groups->{$category};
        if (not defined $lane_group) {
          $self->logger->error(sprintf(
            'lane group not defined for category %s', $category));
        }
        my $nc = $lane_group->circle(
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
        $pos->{id}                                 = $dot_node_name;
        $pos->{type}                               = 'node';
        $previous_pos->{$category}                 = $pos;
        $nodes_by_sortval->{$sv}->{$dot_node_name} = $pos;
        $rails->{$category}->{$dot_node_name}      = $pos;
      }
      # if we by-pass the if block, we need to know the $pos value
      $pos = $nodes_by_sortval->{$sv}->{$dot_node_name};

      $ph->set_props(
        detail_width  => $detail_width,
        detail_height => $detail_height,
        categories    => $categories,
        min_date      => $min_date,
        max_date      => $max_date,
        ymax          => $ymax,
        xmax          => $xmax,
      );
      my $detail_pos = $ph->find_detail_position($event, $pos, $dot_node_name);
      # Draw dashed line from timeline dot to detail box$categories,
      # Draw the line to the corner, not the center.

    }
    $self->logger->trace("svg is currently " . $graph->xmlify);
  }

  method _create_detail_node_for_event ($event, $pos, $node_pos) {

    my $category = $pos->{category};

    $edges_group->line(
      x1    => $node_pos->{x},
      y1    => $node_pos->{y},
      x2    => $pos->{x} - $pos->{width} / 2,
      y2    => $pos->{y} - $pos->{height} / 2,
      class => "timeline detail-edge $category",
    );

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
      id     => sprintf('return-%s', $event->id),
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
        class =>
          'description spectrum-Body spectrum-Body--sizeS spectrum-Body--serif'
      );
      $cc->cdata_noxmlesc($event->description);
    }

    if (defined($event->sources) && scalar(@{ $event->sources })) {
      $div->tag(
        'div',
        class =>
          'sources spectrum-Body spectrum-Body--sizeS spectrum-Body--serif',

      )->cdata_noxmlesc(sprintf(
        '<a  href="#footnotes-%s" class="%s">Sources and References</a>',
        $event->id, 'spectrum-Link spectrum-Link--quiet spectrum-Link--primary',
      ));
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

}
1;
__END__
