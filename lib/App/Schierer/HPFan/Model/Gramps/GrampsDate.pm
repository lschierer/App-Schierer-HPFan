use v5.42.0;
use experimental qw(class);
use utf8::all;
require Date::Manip;
require Scalar::Util;
require App::Schierer::HPFan::Model::Gramps::DateHelper;

class App::Schierer::HPFan::Model::Gramps::GrampsDate :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    'cmp'      => \&_op_cmp,
    'eq'       => \&_op_eq,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    fallback   => 1,
    'nomethod' =>
    sub { $_[0]->logger->logcroak("No overload method for $_[3]") };

  # Single date (partial ok)
  field $year  : param : reader //= 0;
  field $month : param : reader //= 0;    # 1..12 or 0 unknown
  field $day   : param : reader //= 0;    # 1..31 or 0 unknown

  # Range (if present) – same semantics, partials allowed
  field $start : param : reader //= undef;    # another GrampsDate or undef
  field $end   : param : reader //= undef;

  ADJUST {
    if (defined($start)) {
      $self->logger->debug("found a defined start date: " . ref($start));

    }
    if (defined($end)) {
      $self->logger->debug("found a defined end date: " . ref($end));

    }
  }

  # Metadata from Gramps
  field $calendar : param //= 0;    # 0=Gregorian, 1=Julian (per your note)
  field $modifier : param : reader //= 0;    # enum from Gramps (0=exact/none)
  field $quality  : param : reader //= 0;    # enum from Gramps
  field $newyear  : param //= 0;
  field $text     : param : reader //= '';         # freeform
  field $sortval  : param : reader //= 0;          # unix epoch if set
  field $type     : param : reader //= 'single';   # 'single' | 'range' | 'span'

  # ---------- Introspection ----------
  method has_year  { $year  && $year > 0 }
  method has_month { $month && $month > 0 }
  method has_day   { $day   && $day > 0 }

  method precision {
    return 'none' unless $self->has_year;
    return 'y'    unless $self->has_month;
    return 'ym'   unless $self->has_day;
    return 'ymd';
  }

  method modifier_label {
    state %MAP = (
      0 => '',           # unset
      1 => 'before',
      2 => 'after',
      3 => 'about',
      4 => 'between',    # often paired with a range elsewhere
      5 => 'from',       # “from <date>” (may need “to <date>” in ranged form)
    );
    my $m = $modifier // 0;
    return $MAP{$m} // '';    # fallback empty for UI; optionally warn in dev
  }

  method quality_label {
    state %MAP = (
      0 => '',              # unset
      1 => 'estimated',     # lower confidence
      2 => 'calculated',    # derived from other facts
    );
    my $q = $quality // 0;
    return $MAP{$q} // '';
  }

  method is_range {
    defined($start) || defined($end) || $type =~ /^(?:range|span)$/;
  }

  # Monotone ordinal for ordering; no calendar lib needed.
  sub _ord    ($y, $m, $d) { ($y || 0) * 372 + (($m || 1) * 31) + ($d  || 1) }
  sub _ord_hi ($y, $m, $d) { ($y || 0) * 372 + (($m || 12) * 31) + ($d || 31) }

  # Interval key: [lo_ord, lo_excl, hi_inf, hi_ord, hi_excl]
  sub _cmp_tuple ($self) {
    if ($self->type eq 'single') {
      my ($y, $m, $d) = ($self->year, $self->month, $self->day);
      my $mod = $self->modifier // 0;
      if ($mod == 1) {
        return [-9**9, 0, 0, _ord($y, $m, $d), 1];
      }    # before: (-∞, X)
      elsif ($mod == 2) {
        return [_ord($y, $m, $d), 1, 1, 9**9, 0];
      }    # after:  (X, +∞)
           # about: treat as exact for ordering (or widen if desired)
      my $lo = _ord($y, $m, $d);
      my $hi = _ord_hi($y, $m, $d);
      return [$lo, 0, 0, $hi, 0];
    }

    # range/span
    my ($s, $e) = ($self->start, $self->end);
    my ($sy, $sm, $sd) = $s ? ($s->year, $s->month, $s->day) : (0, 0, 0);
    my $lo = _ord($sy, $sm, $sd);

    my $mod = $self->modifier // 0;
    if ($mod == 5 && !$e) {    # FROM A
      return [$lo, 0, 1, 9**9, 0];    # [A, +∞)
    }
    if ($e) {
      my ($ey, $em, $ed) = ($e->year, $e->month, $e->day);
      my $hi = _ord_hi($ey, $em, $ed);
      return [$lo, 0, 0, $hi, 0];     # closed [A, B] (BETWEEN too)
    }
    return [-9**9, 0, 1, 9**9, 0];    # unknown↔∞
  }

  sub _op_cmp ($a, $b, $swap) {
    # Fallback if RHS isn't comparable: compare strings
    return (($swap ? "$b" : "$a") cmp($swap ? "$a" : "$b"))
      unless (defined $a
      && defined $b
      && eval { $a->can('_cmp_tuple') && $b->can('_cmp_tuple') });

    my $A = $a->_cmp_tuple;
    my $B = $b->_cmp_tuple;

    my $cmp =
      ($A->[0] <=> $B->[0]) ||    # lo_ord
      ($A->[1] <=> $B->[1]) ||    # lo_excl (inclusive first)
      ($A->[2] <=> $B->[2]) ||    # hi_inf  (finite before infinite)
      ($A->[3] <=> $B->[3]) ||    # hi_ord
      ($A->[4] <=> $B->[4]);      # hi_excl
    return $swap ? -$cmp : $cmp;
  }

  sub _op_eq ($a, $b, $swap) {
    # undef handling
    return (!defined($a) && !defined($b)) ? 1 : 0
      unless (defined $a && defined $b);

    # If either side is not a GrampsDate, fall back to string eq.
    return (("$a") eq ("$b"))
      unless (blessed($a)
      && blessed($b)
      && $a->isa(__PACKAGE__)
      && $b->isa(__PACKAGE__));

    # Both sides are GrampsDate: compare tuple elements exactly.
    my $A = $a->_cmp_tuple;
    my $B = $b->_cmp_tuple;
    return 0 unless @$A == @$B;
    for my $i (0 .. $#$A) {
      return 0 if $A->[$i] != $B->[$i];
    }
    return 1;
  }

  # ---------- Safe formatting ----------
  # Returns a string always; never warns
  method to_string {
    my $mod = $self->modifier_label;
    $self->logger->debug("date is modified: '$mod'") if length($mod);

    my $qual = $self->quality_label;
    $self->logger->debug("date is qualified: '$qual'") if length($qual);

    my $dm   = $self->as_dm_date;
    my $prec = $self->precision;
    my $base = 'Unknown';

    if ($dm) {
      $base =
          $prec eq 'ymd' ? $dm->printf('%Y-%m-%d')
        : $prec eq 'ym'  ? $dm->printf('%Y-%m')
        :                  $dm->printf('%Y');
    }

    if ($self->is_range) {
      my ($a, $b) = ($start, $end);
      my $A = $a ? $a->_fmt_single() : 'Unknown';
      my $B = $b ? $b->_fmt_single() : 'Unknown';

      # Choose wording based on $type / modifier
      return "From $A to $B" if $type eq 'range';    # FROM..TO
      return "Between $A and $B"
        if $type eq 'span';    # BET..AND (pick your naming)
      return "$A – $B";        # fallback
    }

    my @parts = grep {length} ($qual, $mod,);
    return @parts ? join(' ', @parts) . ' ' . $base : $base;
  }

  method _fmt_single {
    return 'Unknown' unless $self->has_year;
    return sprintf('%04d',           $year) if $self->precision eq 'y';
    return sprintf('%04d-%02d',      $year, $month) if $self->precision eq 'ym';
    return sprintf('%04d-%02d-%02d', $year, $month, $day);    # ymd
  }

  # ---------- Sorting ----------
  # Prefer DB sortval; else derive a comparable numeric key.
  method sort_key {
    return $sortval if $sortval && $sortval > 0;

    # Derive: for partials, assume first of month/year.
    my ($y, $m, $d) = ($year || 0, $month || 1, $day || 1);
    return $y * 10000 + $m * 100 + $d;    # simple integer key (YYYYMMDD)
  }

  # ---------- Optional Date::Manip::Date (full only) ----------
  method as_dm_date {
    my $err;
    my $d = Date::Manip::Date->new;
    if ($self->precision eq 'ymd') {
      $err = $d->parse(sprintf('%04d-%02d-%02d', $year, $month, $day));
    }
    elsif ($self->precision eq 'ym') {
      $err = $d->parse(sprintf('%04d-%02d-01', $year, $month,));
    }
    elsif ($self->precision eq 'y') {
      $err = $d->parse(sprintf('%04d-01-01', $year));
    }elsif($self->is_range && defined($start)){
      my $r;
      if(Scalar::Util::blessed($start) eq 'App::Schierer::HPFan::Model::Gramps::GrampsDate'){
        $r = $start->as_dm_date;
        if(defined $r){
          return $r;
        }
      }
      if(Scalar::Util::blessed($end) eq 'App::Schierer::HPFan::Model::Gramps::GrampsDate'){
        $r = $end->as_dm_date;
        if(defined $r){
          return $r;
        }
      }
      $self->logger->warn("Range defined without start or end dates!!");
      return undef;
    }
    else {
      $self->logger->warn("no precision on this date");
      return undef;
    }
    if ($err) {
      $self->dev_guard(sprintf(
        'failed to parse date with precision %s: %s',
        $self->precision, $err
      ));
      $self->logger->info(sprintf(
        'year is %s, month is %s, day is %s', $year, $month, $day));
      return undef;
    }
    return $d;
  }
}
