use v5.42.0;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::History::Event {
  use Carp;

  # Uniform interface every event must provide
  field $id         : param : reader //= undef;   # stable key (e.g. "G:E0234" or "Y:file#anchor")
  field $origin     : param : reader //= undef;   # 'gramps' | 'yaml'
  field $type       : param : reader //= undef;   # free text like "Birth" | "Battle" | ...
  field $blurb      : param : reader //= undef;   # 1–2 line teaser (optional)
  field $date_iso   : param : reader //= undef;   # "YYYY[-MM[-DD]]" (partial ok)

  field $date_kind  : param : reader //= undef;
  ## '', 'before', 'after', 'about', 'between', 'from', 'estimated', 'calculated'
  field $sortval    : param : reader //= undef;
  ## numeric sort key (e.g. gramps sortval / computed)
  field $html_desc : param : reader : writer //= undef;
  ## pre-rendered HTML (or undef; see lazy below)
  field $sources : param : reader : writer //= [];
  ## arrayref of sources (structs/strings)

  method as_hashref {
    my $r = {};
    $r->{id}        = $id     unless not defined $id;
    $r->{origin}    = $origin unless not defined $origin;
    $r->{type}      = $type       unless not defined $type       ;
    $r->{blurb}     = $blurb      unless not defined $blurb      ;
    $r->{date_iso}  = $date_iso   unless not defined $date_iso   ;
    $r->{date_kind} = $date_kind  unless not defined $date_kind  ;
    $r->{sortval}   = $sortval    unless not defined $sortval;
    $r->{html_desc} = $html_desc  unless not defined $html_desc;
    $r->{sources}   = [$sources->@*];
    return $r;
  }
}
1;
__END__
