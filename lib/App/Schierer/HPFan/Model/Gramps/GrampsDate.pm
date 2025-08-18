use v5.42.0;
use experimental qw(class);
use utf8::all;
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::DateHelper;

class App::Schierer::HPFan::Model::Gramps::GrampsDate :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    'ne'       => \&_inequality,
    '""'       => \&to_string,
    'fallback' => 1;

  # Single date (partial ok)
  field $year  : param //= 0;
  field $month : param //= 0;    # 1..12 or 0 unknown
  field $day   : param //= 0;    # 1..31 or 0 unknown

  # Range (if present) – same semantics, partials allowed
  field $start : param :reader //= undef;    # another GrampsDate or undef
  field $end   : param :reader //= undef;

  ADJUST {
    if(defined($start)){
      my $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
      $start = $dh->parse($start);
    }
    if(defined($end)){
      my $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
      $end = $dh->parse($end);
    }
  }

  # Metadata from Gramps
  field $calendar : param //= 0;     # 0=Gregorian, 1=Julian (per your note)
  field $modifier : param : reader //= 0;    # enum from Gramps (0=exact/none)
  field $quality  : param : reader //= 0;    # enum from Gramps
  field $newyear  : param //= 0;
  field $text     : param : reader //= '';            # freeform
  field $sortval  : param : reader //= 0;             # unix epoch if set
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

  method _comparison ($other, $swap = 0) {
    my $otherDate;
    if (ref($other) eq 'App::Schierer::HPFan::Model::Gramps::GrampsDate') {
      $otherDate = $other->as_dm_date;
    }
    elsif (ref($other) eq 'Date::Manip::Date') {
      $otherDate = $other;
    }
    my $dmDate = $self->as_dm_date;
    if (defined($otherDate) && defined($dmDate)) {
      return $dmDate->cmp($otherDate);
    }
    elsif ($other->can('to_string')) {
      return $self->to_string cmp $other->to_string;
    }
    elsif ($self->precision ne 'none') {
      return 1;
    }
    elsif (length($self->precision)) {
      return -1;
    }
    return 1;
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
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
    }
    else {
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
