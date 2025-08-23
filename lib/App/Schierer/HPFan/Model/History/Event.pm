use v5.42.0;
use utf8::all;
use experimental qw(class);
require JSON::PP;
require Scalar::Util;
require DateTime::Calendar::Julian;
require DateTime::Format::DateManip;
require Date::Calc::Object;

class App::Schierer::HPFan::Model::History::Event
  : isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;
  use Date::Calc qw(Date_to_Days);
  use Scalar::Util qw(blessed);
  use overload
    'cmp'      => \&_op_cmp,
    'eq'       => \&_op_eq,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    fallback   => 1,
    'nomethod' => sub {
    my ($self, $other, $swap, $op) = @_;
    $self->logger->warn("No overload method for $op on " . ref($self));
    return ("$self" cmp "$other");
    };

  # Uniform interface every event must provide
  field $id : param : reader;   # stable key (e.g. "G:E0234" or "Y:file#anchor")
  field $origin : param : reader //= undef;    # 'gramps' | 'yaml'
  field $type   : param : reader //=
    undef;    # free text like "Birth" | "Battle" | ...
  field $blurb    : param : reader;              # 1 line teaser
  field $date_iso : param : reader //= undef;    # "YYYY[-MM[-DD]]" (partial ok)
  field $raw_date : param : reader //= undef
    ; # GrampsDate or Date::Manip::Date (the latter when this was created by ::Model::History::Yaml)
  field $event_class : param : reader //= 'generic';

  field $date_kind : param : reader //= undef;
  ## '', 'before', 'after', 'about', 'between', 'from', 'estimated', 'calculated'
  field $sortval : param : reader;
  ## numeric sort key (e.g. gramps sortval / computed)
  field $description : param : reader : writer //= undef;
  ## pre-rendered HTML (or undef; see lazy below)
  field $sources : param : reader : writer //= [];
  ## arrayref of sources (structs/strings)

  field $kind_sort_order;

  ADJUST {
    Readonly::Hash my %temp => {
      'before'     => 1,
      'between'    => 2,
      'about'      => 3,
      'estimated'  => 3,
      'calculated' => 4,
      'after'      => 5,
      'from'       => 5,
    };
    $kind_sort_order = \%temp;
  }

  method print_date {
    my $r = '';
    $r = $date_kind if defined($date_kind);
    if (defined($raw_date)) {
      my $datetype =
          Scalar::Util::blessed($raw_date)
        ? Scalar::Util::blessed($raw_date)
        : 'Scalar';
      if ($datetype eq 'Scalar') {
        $r = sprintf('%s %s', $r, defined($date_iso) ? $date_iso : $sortval);
      }
      elsif ($datetype eq 'Date::Manip::Date') {
        $r = sprintf('%s %s', $r, $raw_date->printf('%Y-%m-%d'));
      }
      elsif ($datetype eq 'App::Schierer::HPFan::Model::Gramps::GrampsDate') {
        $r = $raw_date->to_string;
      }
    }
    else {
      # sortval is a required field.
      $r = sprintf('%s %s', $r, $sortval);
    }
    $r =~ s/^\s+|\s+$//g;
    return $r;
  }

  method to_hash {
    my $r = {};
    $r->{id}          = $id          unless not defined $id;
    $r->{origin}      = $origin      unless not defined $origin;
    $r->{type}        = $type        unless not defined $type;
    $r->{blurb}       = $blurb       unless not defined $blurb;
    $r->{date_iso}    = $date_iso    unless not defined $date_iso;
    $r->{date_kind}   = $date_kind   unless not defined $date_kind;
    $r->{sortval}     = $sortval     unless not defined $sortval;
    $r->{description} = $description unless not defined $description;
    $r->{sources}     = [$sources->@*];
    return $r;
  }

  method TO_JSON {
    my $json =
      JSON::PP->new->utf8->pretty->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }

  method to_string {
    my @parts;

    push @parts, $id          unless not defined $id;
    push @parts, $origin      unless not defined $origin;
    push @parts, $type        unless not defined $type;
    push @parts, $blurb       unless not defined $blurb;
    push @parts, $date_iso    unless not defined $date_iso;
    push @parts, $date_kind   unless not defined $date_kind;
    push @parts, $sortval     unless not defined $sortval;
    push @parts, $description unless not defined $description;
    push @parts, $sources->@*;

    return join '; ', @parts;
  }

  method _kind_rank ($self) {
    my $k = $self->date_kind // '';
    return
      exists $self->{kind_sort_order}{$k} ? $self->{kind_sort_order}{$k} : 999;
  }

  method _op_cmp ($a, $b, $swap = 0) {
  # If RHS is not an Event, coerce to your sortval scale and compare numerically
    unless (defined $b && blessed($b) && $b->isa(__CLASS__)) {
      my $rhs_sv = $self->_coerce_to_sortval($b);
      my $cmp    = ($a->sortval <=> $rhs_sv);
      return $swap ? -$cmp : $cmp;
    }

    my $cmp =
         ($a->sortval <=> $b->sortval)
      || ($a->_kind_rank <=> $b->_kind_rank)
      || (($a->type  // '') cmp($b->type  // ''))
      || (($a->blurb // '') cmp($b->blurb // ''))
      || (($a->id    // '') cmp($b->id    // ''));    # total ordering

    return $swap ? -$cmp : $cmp;
  }

  method _op_eq ($a, $b, $swap = 0) {
    return 0 unless defined $a && defined $b;
    if (blessed($b) && $b->isa(__CLASS__)) {
      return
           ($a->sortval == $b->sortval)
        && ($a->_kind_rank == $b->_kind_rank)
        && (($a->type  // '') eq ($b->type  // ''))
        && (($a->blurb // '') eq ($b->blurb // ''))
        && (($a->id    // '') eq ($b->id    // '')) ? 1 : 0;
    }
    my $rhs_sv = _coerce_to_sortval($b);
    return ($a->sortval == $rhs_sv) ? 1 : 0;
  }

  method _coerce_to_sortval ($rhs) {
    return 9**9 unless defined $rhs;
    return $rhs +0 if Scalar::Util::looks_like_number($rhs);

    if(blessed($rhs) && $rhs->isa('Date::Calc')){
      return 0+ Date_to_Days($rhs->date());
    }

    if (blessed($rhs) && $rhs->isa('Date::Manip::Date')) {
      my $dt = DateTime::Format::DateManip->parse_datetime($rhs);
      my $jd = DateTime::Calendar::Julian->from_object(object => $dt)->jd;
      return $jd +0;    # same JDN scale as your sortval
    }

    if (!ref $rhs) {
      my $od  = Date::Manip::Date->new;
      my $err = $od->parse($rhs);
      return 9**9 if $err;
      my $dt = DateTime::Format::DateManip->parse_datetime($od);
      my $jd = DateTime::Calendar::Julian->from_object(object => $dt)->jd;
      return $jd +0;
    }

    return 9**9;
  }

}
1;
__END__
