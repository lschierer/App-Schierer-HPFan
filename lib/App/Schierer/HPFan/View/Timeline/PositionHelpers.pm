use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require HTML::Strip;

class App::Schierer::HPFan::View::Timeline::PositionHelpers
  : isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any min max firstidx pairwise);
  use Scalar::Util   qw(blessed);
  #something about this package requies that it be used not just required
  use SVG;
  use Readonly;
  use Math::Trig ':pi';
  use POSIX qw(ceil);
  use Carp;
  use App::Schierer::HPFan::View::Timeline::Utilities
    qw(get_category_for_event);

  # hash at distance radius,
  # each containing an array of { x => $x, y => $y, radius => $r }
  field $used_positions = [];
  field $boxes : reader = {};
  field $event_by_id : reader //= {};
  field $cat_by_id //= {};

  field $detail_width  : param : writer;
  field $detail_height : param : writer;
  field $categories    : writer;
  field $min_date      : writer;
  field $max_date      : writer;
  field $ymax          : writer;
  field $xmax          : writer;
  field $pad = 5;

  method set_events ($events) {
    for my $ev (@$events) {
      my $id = $ev->id or next;
      next unless (Scalar::Util::reftype($ev) eq 'OBJECT');
      next unless ($ev->isa('App::Schierer::HPFan::Model::History::Event'));
      my $cat = get_category_for_event($self, $ev, $self->logger);
      $event_by_id->{$id} = $ev;
      $cat_by_id->{$id}   = $cat;
      # If you already know the detail size here, you can cache it:
      # $size_by_id->{$id}  = $self->_calculate_detail_dimensions($ev);
    }
  }

  method set_props (%opts) {
    $detail_width  = $opts{detail_width} if exists $opts{detail_width};
    $detail_height = $opts{detail_heigh} if exists $opts{detail_heigh};
    $categories    = $opts{categories}   if exists $opts{categories};
    $min_date      = $opts{min_date}     if exists $opts{min_date};
    $max_date      = $opts{max_date}     if exists $opts{max_date};
    $ymax          = $opts{ymax}         if exists $opts{ymax};
    $xmax          = $opts{xmax}         if exists $opts{xmax};
  }

  # event is undefined if it is a timeline dot node
  method _get_normalized_position($ymax, $category, $julian) {
    my @catNames = sort keys $categories->%*;
    my $catIndex = firstidx { $_ eq $category } @catNames;

    my $xcord = 10 * ($catIndex + 1);

    my $date_span = $max_date - $min_date;
    # INVERT: Subtract from max to flip the timeline
    my $normalized_y = ($julian - $min_date) / ($max_date - $min_date) * $ymax;
    return {
      x => int($xcord),
      y => int($normalized_y),
    };
  }

  method find_detail_position($event, $timeline_pos, $dot_node_name) {
    # Simple approach: try positions in a predictable spiral pattern
    my $size = $self->_calculate_detail_dimensions($event);

  # --- Generate offset families programmatically ------------------------------

    my $W = $size->{width};
    my $H = $size->{height};

    # Families (as functions of i). Keep them simple & monotone.
    my @xf = (
      sub ($i, $W, $H) { $W * $i },               # strict grid steps
      sub ($i, $W, $H) { $W * (1 + $i / 10) },    # fine gradation
      sub ($i, $W, $H) { $W * (1 + $i / 3) },     # coarse gradation
    );

    my @yf = (
      sub ($i, $W, $H) { $H * $i },
      sub ($i, $W, $H) { $H * (1 + $i / 10) },
      sub ($i, $W, $H) { $H * (1 + $i / 3) },
    );

    # We always want the box to the right of the timeline column.
    my $MIN_X_OFFSET = $W / 4;    # at least 1/2 box-width to the right
    my $MAX_I        = 14;        # more i => more candidates
    my %seen;
    my @candidates;

    for my $i (0 .. $MAX_I) {
      for my $fx (@xf) {
        my $dx = $fx->($i, $W, $H);
        next if $dx < $MIN_X_OFFSET;

        # Straight right
        my $k = int($dx) . ',0';
        push @candidates, [$dx, 0] unless $seen{$k}++;

        for my $fy (@yf) {
          my $dy = $fy->($i, $W, $H);

          # Up-right
          my $k2 = int($dx) . ',' . int(-$dy);
          push @candidates, [$dx, -$dy] unless $seen{$k2}++;

          # Down-right
          my $k1 = int($dx) . ',' . int(+$dy);
          push @candidates, [$dx, +$dy] unless $seen{$k1}++;

        }
      }

      # A few “diagonals” with mixed scales to reduce fallback overlaps
      my $kx = $W * (1 + $i / 10);
      my $ky = $H * (1 + $i / 10);
      if ($kx >= $MIN_X_OFFSET) {
        my $k3 = int($kx) . ',' . int(+$ky);
        push @candidates, [$kx, +$ky] unless $seen{$k3}++;

        my $k4 = int($kx) . ',' . int(-$ky);
        push @candidates, [$kx, -$ky] unless $seen{$k4}++;
      }
    }

  # --- Rank by “nice” proximity to the dot ------------------------------------

# Favor small horizontal movement (keeps leader lines short) but do care about vertical.
    my $score = sub ($dx, $dy) { sqrt($dx * $dx + (0.8 * $dy) * (0.8 * $dy)) };

    # Convert to absolute positions and sort nearest-first
    my @try_positions = map {
      +{
        x => $timeline_pos->{x} + $_->[0],
        y => $timeline_pos->{y} + $_->[1],
      }
    } @candidates;

    @try_positions = sort {
      $score->($a->{x} - $timeline_pos->{x}, $a->{y} - $timeline_pos->{y})
        <=> $score->($b->{x} - $timeline_pos->{x}, $b->{y} - $timeline_pos->{y})
    } @try_positions;

    # Optional: cap the tail for speed if you like
    splice @try_positions, 250 if @try_positions > 250;

    @try_positions = sort {
      my ($dxA, $dyA) =
        ($a->{x} - $timeline_pos->{x}, $a->{y} - $timeline_pos->{y});
      my ($dxB, $dyB) =
        ($b->{x} - $timeline_pos->{x}, $b->{y} - $timeline_pos->{y});

      # scale by box footprint so “one box up” ~ “one box right”
      my $Wx = $size->{width}  || 1;
      my $Hy = $size->{height} || 1;

      # weights: tweak to taste
      my $wx = 1.0;       # horizontal weight
      my $wy = 2.0;       # vertical weight (penalize y more than x)
      my $up = 1.0;       # extra penalty for moving upward (dy < 0)
      my $rt = -0.005;    # slight reward (negative cost) for moving right

      my $costA =
        $wx * ($dxA / $Wx)**2 +
        $wy * ($dyA / $Hy)**2 +
        ($dyA < 0 ? $up * abs($dyA) / $Hy : 0) +
        ($dxA > 0 ? $rt                   : 0);

      my $costB =
        $wx * ($dxB / $Wx)**2 +
        $wy * ($dyB / $Hy)**2 +
        ($dyB < 0 ? $up * abs($dyB) / $Hy : 0) +
        ($dxB > 0 ? $rt                   : 0);

      $costA <=> $costB;
    } @try_positions;

    foreach my $pos (@try_positions) {
      if ($self->_is_position_clear($event, $size, $pos)) {
        $self->logger->debug(sprintf(
          '%s recieved true for pos %s %s',
          $event->id, $pos->{x}, $pos->{y}
        ));
        # store the amount of space we used as well as the center of that space
        $pos->{width}     = $size->{width};
        $pos->{height}    = $size->{height};
        $pos->{id}        = $event->id;
        $pos->{node}      = $dot_node_name;
        $pos->{type}      = 'detail';
        $pos->{desired_y} = $timeline_pos->{y};
        $self->logger->debug(
          sprintf('recording detail position %s',
            Data::Printer::np($pos, multiline => 0))
        );
        push @{$used_positions}, $pos;
        return $pos;
      }
    }

    # Fallback
    my $fb = {
      x         => $timeline_pos->{x} + 400,
      y         => $timeline_pos->{y} + 10,
      desired_y => $timeline_pos->{y},
      width     => $size->{width},
      height    => $size->{height},
      id        => $event->id,
      node      => $dot_node_name,
      type      => 'detail',
    };
    push @{$used_positions}, $fb;
    $self->logger->warn(sprintf(
      'using fallback value for event %s: pos: %s',
      $event->id, Data::Printer::np($fb, multiline => 0)
    ));
    return $fb;
  }

  method _calculate_detail_dimensions($event) {
    my $hs     = HTML::Strip->new();
    my $width  = $detail_width;
    my $height = $detail_height;

    # Maybe wider boxes for long descriptions to reduce wrapping
    if ($event->description && length($hs->parse($event->description)) > 50) {
      $width += 50;
      $height = $self->_calc_height($event, 1);
    }
    else {
      $height = $self->_calc_height($event);
    }
    return { width => $width, height => $height };
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

  method _calc_height($event, $wide = 0) {
    my $line_height              = 15;
    my $chars_per_line           = 45;
    my $short_chars_per_line     = 40;
    my $date_chars_per_line      = 23;
    my $wide_chars_per_line      = 55;
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
      if ($event->description =~ m{<ul\b}i) {
        $self->logger->debug(
          "description list found, shortening line size for " . $event->id);
        $tc = $short_chars_per_line;
      }
      if (my $pc =()= $event->description =~ m{<p\b}gi) {
        $self->logger->debug("$pc paragrahs found for " . $event->id);
        #there is *always* one paragraph for the description.
        $pc = $pc - 1;
        $lines += $pc unless $pc < 0;
      }
      if ($event->description =~ m{<blockquote\b}i) {
        $self->logger->debug(
          "blockquote found, shortening line size for " . $event->id);
        $tc = $short_chars_per_line;
      }

      my $dl = ceil((length($text_only) / $tc));
      $self->logger->debug("description adding $dl to lines for " . $event->id);
      $lines += $dl unless ($dl < 0);
    }

    my $sl = 2;
    $self->logger->debug("sources adding $sl to lines for " . $event->id);
    $lines += $sl unless ($sl < 0);

    my $height = max($detail_height, ($lines * $line_height));
    return $height;

  }

  method relaxer {
    $self->categorize_boxes;
    foreach my $cat (keys %$boxes) {
      my $lane = $boxes->{$cat};
      next unless @$lane;
      $self->relax_lane($lane);
    }
  }

  method categorize_boxes {
    # don't reorder the original unless you truly need to
    my @sorted = sort { ($a->{id} // '') cmp($b->{id} // '') } @$used_positions;

    $self->logger->debug(sprintf('used_positions: %d', scalar(@sorted)));

    # reset boxes
    $boxes = {};

    for my $pos (@sorted) {
      next unless (defined $pos && ref($pos) eq 'HASH' && defined $pos->{id});

      my $category = $cat_by_id->{ $pos->{id} } // 'generic';
      $pos->{category} = $category;
      push @{ $boxes->{$category} }, $pos;
    }
  }

  method relax_lane ($lane) {

  }

  method _count_overlaps ($lane,) {
    my @idx = grep {
      my $b = $lane->[$_];
      $b && defined $b->{y} && defined $b->{height}
    } 0 .. $#$lane;

    @idx = sort { $lane->[$a]{y} <=> $lane->[$b]{y} } @idx;

    my $count = 0;
    for my $k (1 .. $#idx) {
      my ($i,  $j)  = @idx[$k - 1, $k];
      my ($bi, $bj) = @{$lane}[$i, $j];
      my $min_gap = ($bi->{height} + $bj->{height}) / 2 + $pad;
      $count++ if $bj->{y} < $bi->{y} + $min_gap - 0.5;
    }
    return $count;
  }

}
1;
__END__
