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
require Date::Manip;
require Log::Log4perl;
require GraphViz;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;


package App::Schierer::HPFan::Controller::History {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  my $logger;

  sub register($self, $app, $config) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    state $timeline_cache = {
      built   => 0,
      events  => [],
    };

    $app->helper(timeline => sub($c) {
      unless($timeline_cache->{built}) {
        $logger->warn('timeline cache not yet populated.');
        return [];
      }
      return $timeline_cache->{events};
    });

    my $build_timeline = sub {
      return if $timeline_cache->{built};
      $logger->info('Building History timeline from Gramps…');

      my $ge = App::Schierer::HPFan::Model::History::Gramps->new(
        gramps => $app->gramps
      );
      $ge->process();

      $timeline_cache->{events} = $ge->events;
      $timeline_cache->{built}  = 1;

      $logger->info(sprintf 'History timeline built: %d items',
                     scalar @{ $timeline_cache->{events} });
    };

    $app->plugins->on(
      'gramps_initialized' => sub($c, $gramps) {
        $logger->debug(__PACKAGE__ . ' gramps_initialized sub start');
        $build_timeline->();
      }
    );

    if ($app->config('gramps_initialized')) {
      $logger->debug(__PACKAGE__ . ' detects gramps_initialized from config');
      $build_timeline->();
    }

    $app->routes->get('/Harrypedia/History')->to(
      controller => 'History',
      action     => 'timeline_handler',
    );

    $app->add_navigation_item({
      title => 'Timeline of Relevent Events',
      path  => '/Harrypedia/History',
      order => 1,
    });

    # Store in helper for access
    #$app->helper(history_timeline => sub { return $timeline });

  }

  sub timeline_handler ($c) {

    my $timeline = $c->timeline;
    $logger->debug(sprintf('timeline_handler retrieved %s events',
    scalar @$timeline));

    my $svg = App::Schierer::HPFan::View::Timeline->from_events($timeline,
      width => 1200, height => 2400, show_ticks => 1);

    $c->stash(svg => $svg);

    $c->stash(
      svg       => $svg,
      timeline  => $timeline,
      title     => 'Timeline of Relevent Events',
      template  => 'history/timeline',
      layout    => 'default'
    );

    return $c->render;
  }

  sub build_timeline_svg_semantic ($events, $opts={}) {
    my $W = $opts->{width}  // 1400;  # only used for viewBox
    my $H = $opts->{height} // 240;
    my $lane_h   = $opts->{lane_height} // 24;
    my $baseline = $H - 40;

    # ----- domain from sortval
    my ($min_sv, $max_sv) = _sortval_extent($events);
    my $pad = 365; # pad ~1 year for breathing room
    $min_sv -= $pad; $max_sv += $pad;
    my $scale = sub($sv) {
      return 40 + ($W-80) * ($sv - $min_sv) / (($max_sv - $min_sv) || 1);
    };

    # ----- normalize & lanes
    my @glyphs;
    for my $e (@$events) {
      my $d = $e->{date};
      my $start_sv = $d->start ? $d->start->sortval : $d->sortval;
      my $end_sv   = $d->end   ? $d->end->sortval   : $start_sv;

      my $x1 = $scale->($start_sv);
      my $x2 = $scale->($end_sv);
      my $w  = $x2 - $x1;
      my $is_range = $d->is_range || ($w > 0);

      push @glyphs, {
        %$e,
        x1=>$x1, x2=>$x2, w=>($is_range ? ($w||1) : 0),
        is_range => $is_range,
        lo_sv => $start_sv, hi_sv => $end_sv,
        classes => _classes_for_event($e),
      };
    }
    _assign_lanes_sv(\@glyphs, $lane_h);

    # ----- SVG with fluid box, no inline paint
    my $svg = SVG->new(
      width  => '100%',
      height => '100%',
      viewBox => sprintf('0 0 %d %d', $W, $H),
      preserveAspectRatio => 'xMidYMid meet',
    );

    # axis baseline (unstyled; CSS will style .axis)
    $svg->line(x1=>40,y1=>$baseline,x2=>$W-40,y2=>$baseline, class=>'axis');

    # year ticks (optional; you can style .tick /.ticklabel in CSS)
    my ($y1) = _year_from_sortval($min_sv);
    my ($y2) = _year_from_sortval($max_sv);
    my $step = _tick_step($y1,$y2);
    for (my $y = int($y1/$step)*$step; $y <= $y2; $y += $step) {
      my $sv = _sv_from_ymd($y,1,1);
      my $x  = $scale->($sv);
      $svg->line(x1=>$x, y1=>$baseline, x2=>$x, y2=>$baseline+6, class=>'tick');
      $svg->text(x=>$x, y=>$baseline+20, class=>'ticklabel', 'text-anchor'=>'middle')->cdata($y);
    }

    # events layer
    my $g = $svg->group(class=>'events');
    for my $ev (@glyphs) {
      my $y = $baseline - ($ev->{lane}+1)*$lane_h;
      my $cls = join ' ', @{$ev->{classes}};
      my $grp = $g->group(
        class => $cls,
        'data-person' => ($ev->{who} // ''),
        'data-id'     => ($ev->{id}  // ''),
      );
      $grp->title->cdata("$ev->{label} — " . $ev->{date}->to_string);

      if ($ev->{is_range}) {
        $grp->line(x1=>$ev->{x1}, y1=>$y, x2=>$ev->{x2}, y2=>$y, class=>'range');
        my $mod = $ev->{date}->modifier_label;
        if ($mod eq 'between') {
          $grp->line(x1=>$ev->{x1}, y1=>$y-6, x2=>$ev->{x1}, y2=>$y+6, class=>'cap');
          $grp->line(x1=>$ev->{x2}, y1=>$y-6, x2=>$ev->{x2}, y2=>$y+6, class=>'cap');
        } elsif ($mod eq 'before') {
          $grp->polygon(points=>_arrow_points($ev->{x2},$y, 'left'), class=>'cap');
        } elsif ($mod eq 'after' || $mod eq 'from') {
          $grp->polygon(points=>_arrow_points($ev->{x1},$y, 'right'), class=>'cap');
        }
      } else {
        # git-style lollipop: stem to baseline + dot
        $grp->line(x1=>$ev->{x1}, y1=>$y, x2=>$ev->{x1}, y2=>$baseline, class=>'stem');
        $grp->circle(cx=>$ev->{x1}, cy=>$y, r=>4, class=>'dot');
      }
    }

    return $svg->xmlify;
  }

  # ---------- helpers (sortval / lanes / classes) ----------

  sub _sortval_extent ($evs) {
    my ($lo,$hi) = (9**9, -9**9);
    for my $e (@$evs) {
      my $d = $e->{date};
      my $s = $d->start ? $d->start->sortval : $d->sortval;
      my $t = $d->end   ? $d->end->sortval   : $s;
      $lo = min($lo, $s);
      $hi = max($hi, $t);
    }
    ($lo,$hi);
  }

  # This matches your “git histogram” goal: avoid overlaps across lanes.
  sub _assign_lanes_sv ($glyphs, $lane_h) {
    my @ends; # per-lane rightmost sortval
    for my $g (sort { $a->{lo_sv} <=> $b->{lo_sv} || $a->{hi_sv} <=> $b->{hi_sv} } @$glyphs) {
      my $placed = 0;
      for my $i (0..$#ends) {
        if ($g->{lo_sv} >= $ends[$i]) {
          $g->{lane} = $i;
          $ends[$i] = max($ends[$i], $g->{hi_sv});
          $placed = 1; last;
        }
      }
      if (!$placed) {
        $g->{lane} = @ends;
        push @ends, $g->{hi_sv};
      }
    }
  }

  # Compose semantic classes:
  #  - event type: birth|death|other
  #  - qualifier: estimated|calculated
  #  - modifier: before|after|between|from
  #  - shape: range|point
  #  - color-* from your tags/person metadata
  sub _classes_for_event ($e) {
    my @c = ('event');
    push @c, ($e->{type} // 'other');

    my $m = $e->{date}->modifier_label;     push @c, $m if $m;
    my $q = $e->{date}->quality_label;      push @c, $q if $q;
    push @c, ($e->{date}->is_range ? 'range' : 'point');

    if (my $tags = $e->{tags}) {
      for my $t (@$tags) { push @c, "color-$t" }
    }
    \@c;
  }

  # simple arrow triangles
  sub _arrow_points ($x,$y,$dir) {
    my $s = 7;
    return $dir eq 'left'
      ? sprintf("%f,%f %f,%f %f,%f", $x, $y, $x-$s, $y-$s/1.6, $x-$s, $y+$s/1.6)
      : sprintf("%f,%f %f,%f %f,%f", $x, $y, $x+$s, $y-$s/1.6, $x+$s, $y+$s/1.6);
  }

  # Coarse conversion helpers (only for ticks)
  sub _year_from_sortval ($sv) { int($sv/365.2425) - 4713 } # rough JDN→year; OK for tick spacing
  sub _sv_from_ymd ($y,$m,$d) { _approx_jdn($y,$m,$d) }     # rough inverse, good enough for ticks

  # Very rough JDN approximation for ticks (your real data already has sortval)
  sub _approx_jdn ($y,$m,$d) {
    # Fliegel–Van Flandern algorithm (integer math)
    my $a = int((14 - $m)/12);
    my $yy = $y + 4800 - $a;
    my $mm = $m + 12*$a - 3;
    return $d + int((153*$mm + 2)/5) + 365*$yy + int($yy/4) - int($yy/100) + int($yy/400) - 32045;
  }

}
1;
__END__
