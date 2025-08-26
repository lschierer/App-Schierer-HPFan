use v5.42.0;
use experimental qw(class);
use utf8::all;
require Data::Printer;
require Date::Calc::Object;
require Scalar::Util;

class App::Schierer::HPFan::Model::CustomDate :
  isa(App::Schierer::HPFan::Logger) {
  use Date::Calc   qw(Date_to_Days);
  use Scalar::Util qw( blessed looks_like_number);
  use Carp;
  use Readonly;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,              # string equality
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $text       : param;
  field $is_range   : param : reader //= 0;
  field $modifiers  : writer;
  field $qualifiers : writer;
  field $start      : reader;
  field $end        : reader;

# output fields
  field $year     : reader;
  field $month    : reader;
  field $day      : reader;
  field $complete : reader = 1;
  field $sortval  : reader;

# internal fields
  field $dc;
  field $lo_jdn //= undef;
  field $hi_jdn //= undef;

  field $modifier_enum;
  field $quality_enum;
  field $modifier_rev;
  field $quality_rev;

  ADJUST {
    Readonly::Hash my %m => (
      1 => 'before',
      2 => 'after',
      3 => 'about',
      4 => 'between',
      5 => 'from',
    );
    Readonly::Hash my %q => (
      1 => 'estimated',
      2 => 'calculated',
    );
    $modifier_enum = \%m;
    $quality_enum  = \%q;

    # reverse maps: label -> code (optional, handy if you ever need codes)
    my %mr = map { $m{$_} => $_ } keys %m;
    my %qr = map { $q{$_} => $_ } keys %q;
    Readonly::Hash my %mr_ro => %mr;
    Readonly::Hash my %qr_ro => %qr;
    $modifier_rev = \%mr_ro;
    $quality_rev  = \%qr_ro;
  }

  method modifiers {
    return $modifier_enum->{$modifiers}
      if defined($modifiers) && exists $modifier_enum->{$modifiers};
    return undef;
  }

  method qualifiers {
    return $quality_enum->{$qualifiers}
      if defined($qualifiers) && exists $quality_enum->{$qualifiers};
    return undef;
  }

  ADJUST {
    $self->parse();
    $self->set_sortval;
  }

  method type {
    my $m = lc($self->modifiers // '');
    return 'span'  if $is_range && $m eq 'between';
    return 'range' if $is_range;                      # 'from' or generic range
    return 'single';
  }

  method set_start ($newStart) {
    $self->logger->logcroak('start must be CustomDate')
      unless (blessed($newStart) && $newStart->isa(__CLASS__));
    $start = $newStart;
    $self->set_sortval;
  }

  method set_end ($newEnd) {
    $self->logger->logcroak('end must be CustomDate')
      unless (blessed($newEnd) && $newEnd->isa(__CLASS__));
    $end = $newEnd;
    $self->set_sortval;
  }

  method set_sortval {
    if ($is_range) {
      my $s = defined $start ? $start->sortval : 0;
      my $e = defined $end   ? $end->sortval   : undef;

      if (!defined $e) {
        # open-ended policy: 100-year span forward from start
        my $SPAN = 36525;
        $e = $s + $SPAN;
      }
      $sortval = ($s + $e) / 2;
    }
    else {
      $sortval = $self->gregorian_to_jdn();
    }
  }

  method parse {
    $complete = 1;

    if (ref($text) eq 'HASH') {
      if (exists $text->{dateval}) {
        my $dv = $text->{dateval};

        # set mapped modifier/quality (enums → strings via your maps)
        $modifiers =
          _norm_label($text->{modifier}, $modifier_enum);    # label or undef
        $qualifiers =
          _norm_label($text->{quality}, $quality_enum);      # label or undef

        # start triple
        my ($d1, $m1, $y1) = ($dv->[0] || 1, $dv->[1] || 1, $dv->[2] || 0);
        my $iso_start = _iso_from_triplet($d1, $m1, $y1);

        if (_has_end_triplet($dv)) {
          # we have an end triple — real range
          my ($d2, $m2, $y2) = ($dv->[4] || 1, $dv->[5] || 1, $dv->[6] || 0);
          my $iso_end = _iso_from_triplet($d2, $m2, $y2);

          # coerce BETWEEN/“span” vs FROM/“range” only via label;
          # you’ll use midpoint later
          $start    = __CLASS__->new(text => $iso_start);
          $end      = __CLASS__->new(text => $iso_end);
          $is_range = 1;

          # keep single fields sensible for to_string
          ($year, $month, $day) = ($y1 || 0, $m1 || 1, $d1 || 1);
          $self->set_sortval;
          return;
        }
        else {
          # no end triple → treat as SINGLE;
          # if the incoming *intended* it as "from/before",
          # keep that semantic only as a modifier (tie-break),
          # not as an open-ended range.
          ($year, $month, $day) = ($y1 || 0, $m1 || 1, $d1 || 1);
          $is_range = 0;

          # normalize broken-data semantics:
          # - if Gramps put modifier==5 ("from")
          # but no end → demote to single+after
          # - if Gramps put modifier==4 ("between")
          # but no end → treat as single (drop 'between')
          if ((lc($modifiers // '') eq 'from')) {
            $modifiers = 'after';
          }    # or 'from' if you prefer label
          if ((lc($modifiers // '') eq 'between')) { $modifiers = '' }

          $sortval = $self->gregorian_to_jdn();    # single = anchor date
          return;
        }
      }
    }
    else {
      $text = $self->_normalize_dashes($text);

      if ($text =~ /\A(\d{3,4})-(\d{1,2})-(\d{1,2})\z/) {
        ($year, $month, $day) = (0+ $1, 0+ $2, 0+ $3);
        $complete = 1;
        return;
      }
      if ($text =~ /\A(\d{3,4})-(\d{1,2})\z/) {
        ($year, $month, $day) = (0+ $1, 0+ $2, 1);
        $complete = 0;
        return;
      }
      if ($text =~ /\A(\d{3,4})\z/) {
        ($year, $month, $day) = (0+ $1, 1, 1);
        $complete = 0;
        return;
      }
      if (my ($cent) = $text =~ /(\d{2})th\b/) {
        ($year, $month, $day) = (($cent - 1) * 100, 1, 1);
        $complete = 0;
        return;
      }

    }

    # Unknown → sentinel but valid
    ($year, $month, $day) = (9999, 12, 1);
    $complete = 0;

  }

 # Build a YYYY-MM-DD string from a Gramps date triple (d,m,y), anchoring zeros.
  sub _iso_from_triplet ($d, $m, $y) {
    my $yy = ($y || 9999);
    my $mm = ($m || 1);
    my $dd = ($d || 1);
    return sprintf('%04d-%02d-%02d', $yy, $mm, $dd);
  }

  # True if dateval carries a non-empty end triple (indices 4..6)
  sub _has_end_triplet ($dv) {
    return (ref($dv) eq 'ARRAY'
        && @$dv >= 7
        && (($dv->[4] || 0) || ($dv->[5] || 0) || ($dv->[6] || 0)));
  }

  method _normalize_dashes ($s) {
    $s =~ s/[\p{Pd}\x{2212}\x{FE63}\x{FF0D}]/-/g;    # all dash-like → '-'
    return $s;
  }

  sub _norm_label ($val, $enum_map) {
    return undef unless defined $val;

    # If numeric enum → map to label
    if (looks_like_number($val)) {
      my $label = $enum_map->{$val};
      return $label if defined $label;
      return undef;    # unknown code → treat as none
    }

    # If already a string → normalize/trust (lowercase & trim)
    my $s = lc($val // '');
    $s =~ s/^\s+|\s+$//g;
    return length $s ? $s : undef;
  }

  # Strict versions if you want to reject unknown labels:
  sub _norm_label_strict ($val, $enum_map) {
    my $s = _norm_label($val, $enum_map);
    return undef unless defined $s;
    my %allowed = map { $enum_map->{$_} => 1 } keys %$enum_map;
    return $allowed{$s} ? $s : undef;
  }

  method gregorian_to_jdn {
    unless($year > 0) {
      $year = 9999;
      $month = 12;
      $day = 31;
    }

    $year  = sprintf('%04d', $year);
    $month = sprintf('%02d', $month);
    $day   = sprintf('%02d', $day);
    my $rd =
      Date_to_Days($year +0, ($month || 1) +0, ($day || 1) +0);    # Rata Die
    my $jdn = $rd + 1721425;    # convert to JDN
    $self->logger->debug(
      "gregorian_to_jdn year $year month $month day $day rd: $rd jdn: $jdn");
    return $jdn;
  }

  method _comparison ($other, $swap = 0) {
    my ($a, $b) = $swap ? ($other, $self) : ($self, $other);

    if (blessed($a) && $a->isa(__CLASS__) && blessed($b) && $b->isa(__CLASS__))
    {
      # 1) primary: canonical JDN midpoint
      my $svc = $a->sortval <=> $b->sortval;
      return $svc if $svc;

      # 2) modifier rank (domain semantics)
      my $mrc = $a->_modifier_rank <=> $b->_modifier_rank;
      return $mrc if $mrc;

      # 3) quality rank (certainty hint)
      my $qrc = $a->_quality_rank <=> $b->_quality_rank;
      return $qrc if $qrc;

      # 4) (optional) prefer more precise dates when everything else ties
      my $prc = $a->_precision_rank <=> $b->_precision_rank;
      return $prc if $prc;

      # 5) final stable tie-breaker: string form
      return $a->to_string cmp $b->to_string;
    }

    # Fallback: string compare against non-CustomDate RHS
    return "$a" cmp "$b";
  }

  method _equality ($other, $swap = 0) {
    return 0 unless blessed($other) && $other->isa(__CLASS__);

    # Equal singles if same anchor date
    if (!$self->is_range && !$other->is_range) {
      $self->logger->debug(sprintf(
        'comparing %s to %s for equality',
        $self->sortval, $other->sortval
      ));
      return ($self->sortval == $other->sortval) ? 1 : 0;
    }

    # Equal ranges if both endpoints match
    if ($self->is_range && $other->is_range) {
      return ($self->start->sortval == $other->start->sortval
          && $self->end->sortval == $other->end->sortval) ? 1 : 0;
    }

    return 0;
  }

  method to_string {
    if ($is_range && defined $start && defined $end) {
      my @p;
      push @p, $self->qualifiers if defined $self->qualifiers;
      my $m = lc($self->modifiers // '');
      if ($m eq 'between') {
        push @p, 'between', $start->toISO, 'and', $end->toISO;
      }
      else {
        push @p, 'from', $start->toISO, 'to', $end->toISO;
      }
      return join ' ', @p;
    }
    my @parts;
    push @parts, $self->modifiers if defined $self->modifiers;
    push @parts, sprintf('%s-%s-%s', $year, $month, $day);
    push @parts, $self->qualifiers if defined $self->qualifiers;
    return join(' ', @parts);
  }

  method toISO($SingleDate = 1) {
    return sprintf('%04d-%02d-%02d', $year || 0, $month || 1, $day || 1)
      if $SingleDate;
    if ($is_range && defined($start) && defined($end)) {
      my $s = defined($start) ? $start->toISO : '0000-01-01';
      my $e = defined($end)   ? $end->toISO   : '9999-12-31';
      return sprintf('%04d-%02d-%02d - %04d-%02d-%02d', $s, $e);
    }
  }

  method _modifier_rank {
    # before < about < (none/exact) < between==from < after
    state %R = (
      1  => 0,
      3  => 1,
      '' => 2,
      4  => 3,
      2  => 4,
      5  => 4,    # same bucket
    );

    my $m = $modifier_rev->{$modifiers}
      if defined $modifiers && exists $modifier_rev->{$modifiers};
    $m = 2 if not defined $m;
    $m = lc($m);
    $m =~ s/^\s+|\s+$//g;
    my $rank = exists $R{$m} ? $R{$m} : 2;    # unknown -> neutral “exact”
    $self->logger->debug(sprintf(
      'modifiers: %s reved: %s rank %s',
      defined($modifiers) ? $modifiers : 'undef',
      $m, $rank
    ));
    return $rank;

  }

  method _quality_rank {
    # (none) < estimated < calculated
    state %R = (
      ''           => 0,
      'estimated'  => 1,
      'calculated' => 2,
    );
    my $q = lc($self->qualifiers // '');
    $q =~ s/^\s+|\s+$//g;
    return $R{$q} // 0;
  }

  # (optional) precision tiebreaker: more precise first (ymd < ym < y)
  method _precision_rank {
    # lower is "better/earlier" in sort order
    return
        ($self->day   // 0) ? 0
      : ($self->month // 0) ? 1
      :                       2;
  }

}
1;
__END__

-- Count singles vs ranges
SELECT
  SUM(CASE WHEN json_array_length(json_extract(json_data,'$.dateval')) >= 7
            AND (COALESCE(json_extract(json_data,'$.dateval[4]'),0)<>0
              OR COALESCE(json_extract(json_data,'$.dateval[5]'),0)<>0
              OR COALESCE(json_extract(json_data,'$.dateval[6]'),0)<>0)
           THEN 1 ELSE 0 END) AS ranges,
  SUM(CASE WHEN json_array_length(json_extract(json_data,'$.dateval')) < 7
           THEN 1 ELSE 0 END) AS singles
FROM event;

SELECT gramps_id
FROM event
WHERE json_type(json_extract(json_data,'$.dateval'))='array'
  AND json_array_length(json_extract(json_data,'$.dateval')) < 7
  AND COALESCE(json_extract(json_data,'$.modifier'),0) IN (4,5);

  SELECT gramps_id
  FROM event
  WHERE json_type(json_extract(json_data,'$.dateval'))='array'
    AND json_array_length(json_extract(json_data,'$.dateval')) >= 7
    AND COALESCE(json_extract(json_data,'$.dateval[4]'),0)=0
    AND COALESCE(json_extract(json_data,'$.dateval[5]'),0)=0
    AND COALESCE(json_extract(json_data,'$.dateval[6]'),0)=0;
