use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require GraphViz2;
require Pandoc;

class App::Schierer::HPFan::View::Timeline
  : isa(App::Schierer::HPFan::Logger) {
  use SVG;
  use List::AllUtils qw( any min max firstidx );
  use Scalar::Util   qw(blessed);

  #field $top_pad        : param //= 40;
  #field $bottom_pad     : param //= 40;
  #field $left_pad       : param //= 80;
  #field $col_gap        : param //= 140;
  #field $lane_jitter    : param //= 10;
  #field $SHOW_TICKS     : param //= 1;
  #field $tick_step      : param //= undef;

  field $name : param //= 'Timeline';

  field $events : param //= [];

  # internal fields
  field $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );
  field $parser = Pandoc->new();

  field $categories       = {};
  field $nodes_by_sortval = {};
  field $category_offset  = {};

  field $subgraph_opts = {
    rank    => 'min',
    margin  => 5,
  };

  field $graph_opts = {
    bgcolor   => "transparent",
    layout    => 'fdp',
    #rankdir   => 'TB',
    overlap   => '3:false',
    splines   => 'line',
    concentrate => 'false',
    inputscale  => 72,
    #diredgeconstraints  => 'true',
    #mode          => "hier",
    sep           => 10,
    start    => "random",
  };

  field $node_opts = {
    fillcolor => "transparent",

  };

  field $global_opts = {
    directed => 1,
    format   => 'svg',
    name     => $name,
    strict   => 1,
  };

  field $base_x = 10; # I decided 100 was too much separation
  #default this to a very high number that should be bigger than my julian dates.
  field $base_y = 9**9;

  field $min_date = 9**9;
  field $max_date = 0;

  # output fields
  field $graph : reader;

  ADJUST {
    srand(time);
    $graph = GraphViz2->new(
      global   => $global_opts,
      graph    => $graph_opts,
      subgraph => $subgraph_opts,
      logger   => $self->logger,
      node     => $node_opts,

    );
  }

  method get_program {
    return $graph->dot_input() //'Run failed';
  }

  method create {
    $self->_organize_events_by_category_and_date();
    #$self->_create_timeline_dot_nodes();
    $self->_create_detail_nodes_and_connections();
    $self->_create_timeline_edges();

    $graph->run();
    return $self->_process_svg_output();
  }

  field $previous_y_cords = {};

  # event is undefined if it is a timeline dot node
  method _get_normalized_position($category, $julian, $event = undef) {
      my @catNames = keys $categories->%*;
      my $catIndex = firstidx {$_ eq $category } @catNames;

      my $xcord = 10 * $catIndex;

      if (defined($event)) {
          # Detail node spreading logic
          my @events_on_date = @{ $categories->{$category}->{$event->sortval} };
          my $event_index = firstidx { $_->id eq $event->id } @events_on_date;
          my $num_events = @events_on_date;

          my $detail_start = $xcord + 50;
          my $detail_width = 800;
          my $separation = 100 / $num_events;

          if ($num_events == 1) {
              $xcord = int( $detail_start + $separation );
          } else {
              $xcord = int( $detail_start + abs( (  rand($event_index + 1) * $separation ) ) );
          }
      }

      my $date_span = $max_date - $min_date;
      # INVERT: Subtract from max to flip the timeline
      # Use a generous spacing for your current sample
      my $pixels_per_event = 100;  # Plenty of room for testing
      my $current_event_count = scalar @{ $events };
      my $estimated_height = $current_event_count * $pixels_per_event;

      my $normalized_y = 100 + (($max_date - $julian) / $date_span) * $estimated_height;

      return {
          x => int($xcord),
          y => int($normalized_y),
      };
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
      $base_y = min($base_y, $event->sortval);
      $min_date = min($min_date, $event->sortval);
      $max_date = max($max_date, $event->sortval);

      push @{ $categories->{$category}->{$date} }, $event;
    }
  }

  method _create_detail_nodes_and_connections {
      my @catNames = keys $categories->%*;
      foreach my $index (0 .. $#catNames) {
        my $category = $catNames[$index];

          foreach my $date (keys $categories->{$category}->%*) {
            next if exists $nodes_by_sortval->{$date};
              my $dot_node_name = "dot_${category}_${date}";
              my @events_on_date = @{ $categories->{$category}->{$date} };
              my $pos = $self->_get_normalized_position($category, $date);

              # Create subgraph for this date (no cluster_ prefix = no visual clustering)
              $graph->push_subgraph(name => "date_$date");

              $graph->add_node(
                name   => $dot_node_name,
                xlabel => $date,
                shape  => 'point',
                style  => 'filled',
                class  => $category,
                pos    => sprintf('%s,%s!', $pos->{x}, $pos->{y}),
                pin    => 'true',
              );
              $nodes_by_sortval->{$date}  = {};

              foreach my $event (@events_on_date) {
                # do not generate detail nodes until the timeline itself displays correctly.
                #$self->_create_detail_node_for_event($event, $dot_node_name, $category);
              }

              $graph->pop_subgraph();
          }
      }
  }

  method _create_detail_node_for_event($event, $dot_node_name, $category) {

      my $sources = scalar($event->sources) ? join('\n', $event->sources->@*) : ' ';

      my @parts;
      push @parts, $event->blurb if defined($event->blurb) && length($event->blurb) > 0;
      push @parts, $event->description if defined($event->description) && length($event->description) > 0;
      push @parts, $sources if scalar($sources) && length($sources) > 0;
      my $label = sprintf('{%s}', join('|', @parts));

      state $detail_offset = 0;
      my $pos = $self->_get_normalized_position($category, $event->sortval, $event);
      my $x_offset = 50;
      my $min_offset = scalar keys $categories->%*;
      $min_offset = $min_offset * 10 + 2;
      #my $xcord = int($min_offset + ( 1 +  (int(rand($x_offset)) ) % $x_offset ) );
      my $xcord = max($min_offset, $pos->{x});
      my $node_name = sprintf('detail_%s', $event->id);
      next if exists $nodes_by_sortval->{$event->sortval}->{$node_name};
      $nodes_by_sortval->{$event->sortval}->{$node_name} = 1;
      $graph->add_node(
          name  => $node_name,
          shape => 'Mrecord',
          label => $label,
          class => $category,
          style => 'filled',
          pos   => sprintf('%s,%s', $xcord, $pos->{y}),
          pin   => 'true',
      );

      $graph->add_edge(
          from => "detail_" . $event->id,
          to => $dot_node_name,
          style     => 'dotted',
          constraint  => "false",
          class       =>"dotted $category",
      );
  }


  method _create_timeline_edges {
    my @catNames = keys $categories->%*;
    foreach my $index (0 .. $#catNames) {
      my $category = $catNames[$index];
      my @dates    = sort keys $categories->{$category}->%*;

      for my $i (0 .. $#dates - 1) {
        my $to_dot    = "dot_${category}_$dates[$i]";
        my $from_dot  = "dot_${category}_$dates[$i + 1]";
        my $date1 = $dates[$i];
        my $date2 = $dates[$i + 1];
        my $delta = $date2 - $date1;

        $self->logger->debug(
          sprintf('Creating timeline edge: %s -> %s; date1: %s, date2: %s, delta: %s',
          $from_dot, $to_dot, $date1, $date2, $delta));

        $graph->add_edge(
          from      => $from_dot,
          to        => $to_dot,
          style     => 'solid',
          class     => $category,
          dir       => 'none',
          arrowhead => 'none',
          arrowtail => 'none',
          minlen       => $delta,
          constraint  => "true",
          weight      => $delta,
        );
      }
    }
  }

  method _process_svg_output {
    my $svg = $graph->dot_output();
    $self->logger->debug(sprintf('Generated DOT: %s', $graph->dot_input));

    # Your existing SVG cleanup
    $svg =~ s/(stroke|fill)="black"//g;
    $svg =~ s/(stroke|fill)="none"//g;
    $svg =~ s/<svg ([^>]*)width="[^"]*"/<svg $1/;
    $svg =~ s/<svg ([^>]*)height="[^"]*"/<svg $1/;
    $svg =~ s/<svg /<svg preserveAspectRatio="xMidYMid meet" width="100%" height="100%" /;
    $svg =~ s/<text ([^>]+) font-family="[^"]+" font-size="[^"]+">/<text $1 class="spectrum-Heading spectrum-Heading--size-M spectrum-Heading--serif">/g;
    return $svg;
  }
}
1;
__END__

# Build a vertical "git graph"-like SVG.
# $events  = arrayref of App::Schierer::HPFan::Model::History::Event
# %opts:
#   width, height                 : viewBox only; CSS controls actual rendered size
#   top_pad, bottom_pad, left_pad : paddings
#   col_gap                       : gap between type columns
#   lane_jitter                   : +/- px horizontal jitter to separate collisions within a column
#   order                         : optional arrayref of type labels to fix column order
#   show_year_ticks               : 1/0
#   tick_step                     : optional year step override
sub from_events ($class, $events, %opts) {
  my $W  = $opts{width}        // 1200;
  my $H  = $opts{height}       // 700;
  my $TP = $opts{top_pad}      // 40;
  my $BP = $opts{bottom_pad}   // 40;
  my $LP = $opts{left_pad}     // 80;
  my $CG = $opts{col_gap}      // 140;
  my $J  = $opts{lane_jitter}  // 10;
  my $SHOW_TICKS = exists $opts{show_year_ticks} ? !!$opts{show_year_ticks} : 1;
  my $TICK_STEP  = $opts{tick_step}; # optional

  # ---- column layout (types -> x)
  my @types = _collect_types($events, $opts{order});
  my %col_x;
  my $cols = @types;
  for my $i (0..$#types) {
    $col_x{ $types[$i] } = $LP + $i * $CG;
  }
  # expand width if needed to fit all cols visibly
  my $used_w = $LP + ($cols ? ($cols-1)*$CG : 0) + 80;
  $W = max($W, $used_w);

  # ---- domain by sortval (JDN)
  my ($min_sv, $max_sv) = _extent_sortval($events);
  my $PAD_D = 365;  # extra ~1y headroom
  $min_sv -= $PAD_D; $max_sv += $PAD_D;

  my $scaleY = sub ($sv) {
    my $h = ($H - $TP - $BP) || 1;
    return $TP + $h * ($sv - $min_sv) / (($max_sv - $min_sv) || 1);
  };

  # ---- normalize event glyphs per column
  my %per_col; # type => [ glyphs ]
  for my $ev (@$events) {
    next unless blessed($ev);
    my $t  = _norm_type($ev->type);
    my $gd = $ev->raw_date;

    my ($s_sv,$e_sv,$is_range) = _start_end_sv($ev, $gd);
    my $y1 = $scaleY->($s_sv);
    my $y2 = $scaleY->($e_sv);
    my $h  = $is_range ? max(1, $y2 - $y1) : 0;

    push $per_col{$t}->@*, +{
      ev        => $ev,
      t         => $t,
      y1        => $y1,
      y2        => $y2,
      h         => $h,
      is_range  => $is_range,
      s_sv      => $s_sv,
      e_sv      => $e_sv,
      classes   => _classes_for($ev, $gd, $t),
      # x set later per column with lane jitter
    };
  }

  # ---- lane jitter within each column to avoid perfect overlaps
  # For each column, if two glyphs share (or nearly share) the same y for points,
  # or overlapping vertical spans, give them small +/- X jitters: -J, +J, -2J, +2J, ...
  for my $t (@types) {
    _assign_column_jitter($per_col{$t} // [], $J);
  }

  # ---- SVG skeleton
  my $svg = SVG->new(
    width               => '100%',
    height              => '100%',
    viewBox             => sprintf('0 0 %d %d', $W, $H),
    preserveAspectRatio => 'xMidYMid meet',
  );

  # Year ticks left side
  if ($SHOW_TICKS) {
    my $ymin = _year_from_jdn($min_sv);
    my $ymax = _year_from_jdn($max_sv);
    my $step = defined $TICK_STEP ? $TICK_STEP : _auto_tick_step($ymin,$ymax);
    for (my $y = int($ymin/$step)*$step; $y <= $ymax; $y += $step) {
      my $jdn = _jdn_from_ymd($y,1,1);
      my $yy  = $scaleY->($jdn);
      $svg->line(x1=>$LP-12, y1=>$yy, x2=>$LP-4, y2=>$yy, class=>'tick');
      $svg->text(x=>$LP-16, y=>$yy+4, class=>'ticklabel', 'text-anchor'=>'end')->cdata($y);
    }
  }

  # Column guides and labels
  my $g_cols = $svg->group(class=>'columns');
  for my $t (@types) {
    my $x = $col_x{$t};
    # vertical branch line
    $g_cols->line(x1=>$x, y1=>$TP, x2=>$x, y2=>$H-$BP, class=>"branch $t");
    # label
    $g_cols->text(x=>$x, y=>$TP-12, class=>'collabel', 'text-anchor'=>'middle')->cdata(_pretty_type($t));
  }

  # Events
  my $g_ev = $svg->group(class=>'events');
  for my $t (@types) {
    for my $g (sort { $a->{y1} <=> $b->{y1} || $a->{y2} <=> $b->{y2} } @{ $per_col{$t} // [] }) {
      my $ev = $g->{ev};
      my $x  = $col_x{$t} + ($g->{x_jitter} // 0);
      my $cls = join ' ', @{ $g->{classes} };
      my $grp = $g_ev->group(
        class => $cls,
        'data-id'    => ($ev->id // ''),
        'data-type'  => ($ev->type // ''),
        'data-origin'=> ($ev->origin // ''),
      );

      my $label = $ev->blurb // '';
      my $text  = eval { $ev->raw_date->to_string } // ($ev->date_iso // '');
      $grp->title->cdata($label . (length($text) ? " — $text" : ''));

      if ($g->{is_range}) {
        # vertical segment in the column
        $grp->line(x1=>$x, y1=>$g->{y1}, x2=>$x, y2=>$g->{y2}, class=>'vspan');
        my $mod = eval { $ev->raw_date->modifier_label } // ($ev->date_kind // '');
        if ($mod eq 'between') {
          # bracket caps
          $grp->line(x1=>$x-6, y1=>$g->{y1}, x2=>$x+6, y2=>$g->{y1}, class=>'cap');
          $grp->line(x1=>$x-6, y1=>$g->{y2}, x2=>$x+6, y2=>$g->{y2}, class=>'cap');
        } elsif ($mod eq 'before') {
          _arrow($grp, $x, $g->{y1}, 'up');    # open towards -∞
        } elsif ($mod eq 'after' || $mod eq 'from') {
          _arrow($grp, $x, $g->{y2}, 'down');  # open towards +∞
        }
      } else {
        # lollipop: dot + short horizontal tick to branch
        $grp->circle(cx=>$x, cy=>$g->{y1}, r=>4, class=>'dot');
        $grp->line(x1=>$x-8, y1=>$g->{y1}, x2=>$x+8, y2=>$g->{y1}, class=>'htick');
      }
    }
  }

  return $svg->xmlify;
}

# ---------- helpers ----------

sub _collect_types ($events, $order) {
  if ($order && ref($order) eq 'ARRAY' && @$order) {
    # normalize incoming labels same as _norm_type
    my @norm = map { _norm_type($_) } @$order;
    return @norm;
  }
  my %seen;
  for my $ev (@$events) {
    next unless blessed($ev);
    $seen{ _norm_type($ev->type) }++;
  }
  # stable-ish default order: birth, death, then alpha others
  my @types = sort keys %seen;
  my @front = grep { $_ eq 'birth' || $_ eq 'death' } @types;
  my @rest  = grep { $_ ne 'birth' && $_ ne 'death' } @types;
  # birth, death first, then others alpha
  my %is_front = map { $_=>1 } @front;
  return (grep { $_ eq 'birth' } @types,
          grep { $_ eq 'death' } @types,
          sort grep { !$is_front{$_} } @rest);
}

sub _norm_type ($t) {
  $t //= '';
  my $lc = lc $t;
  return 'birth' if $lc =~ /birth/;
  return 'death' if $lc =~ /death/;
  return $lc || 'other';
}

sub _pretty_type ($t) {
  return 'Birth' if $t eq 'birth';
  return 'Death' if $t eq 'death';
  # capitalize first
  $t =~ s/^(\w)/\U$1/;
  $t;
}

sub _extent_sortval ($evs) {
  my ($lo,$hi) = (9**9, -9**9);
  for my $ev (@$evs) {
    my ($s,$e) = _start_end_sv($ev, $ev->raw_date);
    $lo = min($lo, $s);
    $hi = max($hi, $e);
  }
  ($lo,$hi);
}

sub _start_end_sv ($ev, $gd) {
  my ($s_sv,$e_sv);
  if (blessed($gd) && $gd->can('is_range') && $gd->is_range) {
    $s_sv = $gd->start ? $gd->start->sortval : ($ev->sortval // 0);
    $e_sv = $gd->end   ? $gd->end->sortval   : $s_sv;
  } else {
    $s_sv = $ev->sortval // 0;
    $e_sv = $s_sv;
  }
  my $is_range = ($e_sv != $s_sv) || (blessed($gd) && $gd->is_range);
  return ($s_sv,$e_sv,$is_range);
}

# Within a column, give overlapping glyphs small alternating x-jitters.
sub _assign_column_jitter ($glyphs, $J) {
  return unless @$glyphs;
  # sort by y1 then y2
  my @sorted = sort { $a->{y1} <=> $b->{y1} || $a->{y2} <=> $b->{y2} } @$glyphs;
  my $last_y = -1e9;
  my $bucket = [];
  my $idx = 0;

  my $flush = sub {
    my $n = @$bucket;
    return unless $n;
    # assign jitters: 0, +J, -J, +2J, -2J, ...
    my @seq = (0);
    for my $k (1..int(($n-1+1)/2)) {
      push @seq, ($J*$k, -$J*$k);
    }
    for my $i (0..$n-1) {
      $bucket->[$i]->{x_jitter} = $seq[$i] // 0;
    }
    $bucket = [];
  };

  for my $g (@sorted) {
    if (abs($g->{y1} - $last_y) <= 8) { # near-equal y → same bucket
      push @$bucket, $g;
    } else {
      $flush->();
      $bucket = [$g];
      $last_y = $g->{y1};
    }
    $idx++;
  }
  $flush->();
}

sub _classes_for ($ev, $gd, $norm_t) {
  my @c = ('event', $norm_t);
  if (blessed($gd)) {
    my $q = eval { $gd->quality_label } // '';
    my $m = eval { $gd->modifier_label } // '';
    push @c, $q if $q;          # estimated|calculated
    push @c, $m if $m;          # before|after|between|from
    push @c, ($gd->is_range ? 'range' : 'point');
  } else {
    push @c, 'point';
    my $k = $ev->date_kind // '';
    push @c, $k if $k;
  }
  if ($ev->can('tags') && ref($ev->tags) eq 'ARRAY') {
    push @c, map { "color-$_" } $ev->tags->@*;
  }
  return \@c;
}

# marker arrow at column line
sub _arrow ($grp, $x, $y, $dir) {
  my $s = 7;
  my $p = $dir eq 'up'
    ? sprintf("%f,%f %f,%f %f,%f", $x, $y, $x-$s/1.6, $y-$s, $x+$s/1.6, $y-$s)
    : sprintf("%f,%f %f,%f %f,%f", $x, $y, $x-$s/1.6, $y+$s, $x+$s/1.6, $y+$s);
  $grp->polygon(points=>$p, class=>'cap');
}

# ---- JDN <-> Y/M/D (ticks) ----
sub _ymd_from_jdn ($j) {
  my $l = $j + 68569;
  my $n = int((4 * $l) / 146097);
  my $l2 = $l - int((146097 * $n + 3) / 4);
  my $i = int((4000 * ($l2 + 1)) / 1461001);
  my $l3 = $l2 - int((1461 * $i) / 4) + 31;
  my $j2 = int((80 * $l3) / 2447);
  my $d = $l3 - int((2447 * $j2) / 80);
  my $l4 = int($j2 / 11);
  my $m = $j2 + 2 - 12 * $l4;
  my $y = 100 * ($n - 49) + $i + $l4;
  return ($y,$m,$d);
}
sub _year_from_jdn ($j) { my ($y,undef,undef) = _ymd_from_jdn($j); $y }
sub _jdn_from_ymd ($y,$m,$d) {
  my $a = int((14 - $m)/12);
  my $yy = $y + 4800 - $a;
  my $mm = $m + 12*$a - 3;
  return $d + int((153*$mm + 2)/5) + 365*$yy + int($yy/4) - int($yy/100) + int($yy/400) - 32045;
}
sub _auto_tick_step ($ymin,$ymax) {
  my $span = $ymax - $ymin;
  return $span > 1200 ? 200
       : $span > 600  ? 100
       : $span > 300  ? 50
       : $span > 120  ? 25
       : $span > 60   ? 10
       :                5;
}

1;
