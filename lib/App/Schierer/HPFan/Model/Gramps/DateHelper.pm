use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::GrampsDate;

class App::Schierer::HPFan::Model::Gramps::DateHelper :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Date::Manip;

  # Static methods for parsing and formatting Gramps dates

  # Parse the JSON-ish hash from your DB into a GrampsDate
  method parse ($h) {
    # Common Gramps single-date shape (your example)
    if (exists $h->{dateval} && ref($h->{dateval}) eq 'ARRAY') {
      my ($d, $m, $y, $u) = @{ $h->{dateval} };    # day, month, year, (unused?)
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        year     => $y || 0,
        month    => $m || 0,
        day      => $d || 0,
        calendar => $h->{calendar} // 0,
        modifier => $h->{modifier} // 0,
        newyear  => $h->{newyear}  // 0,
        quality  => $h->{quality}  // 0,
        sortval  => $h->{sortval}  // 0,
        text     => $h->{text}     // '',
        type     => 'single',
      );
    }

# Range/span forms some exports use:
# e.g., { type:'range', start=>{dateval=>[...]...}, end=>{dateval=>[...]...}, ... }
    if (($h->{type} // '') =~ /^(?:range|span)$/i || ($h->{start} || $h->{end}))
    {
      my $start = $h->{start} ? $self->parse($h->{start}) : undef;
      my $end   = $h->{end}   ? $self->parse($h->{end})   : undef;
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        start    => $start,
        end      => $end,
        calendar => $h->{calendar} // 0,
        modifier => $h->{modifier} // 0,
        newyear  => $h->{newyear}  // 0,
        quality  => $h->{quality}  // 0,
        sortval  => $h->{sortval}  // 0,
        text     => $h->{text}     // '',
        type     => (lc($h->{type} // 'range')),
      );
    }

# Fallback: try plaintext in {text} if present (“ABT 1900”, “BET 1890 AND 1895”, etc.)
    if (defined $h->{text} && length $h->{text}) {
      my ($gd) = $self->_from_free_text($h->{text}, $h);
      return $gd if $gd;
    }

    # Unknown/empty
    return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
      type => 'single',);
  }

  # very small parser for common GED/Gramps textual forms; expand as needed
  method _from_free_text ($txt, $meta) {
    # EXACT YYYY-MM-DD or YYYY-MM or YYYY
    if ($txt =~ /\b(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?\b/) {
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        year  => $1 +0,
        month => ($2 || 0) +0,
        day   => ($3 || 0) +0,
        %$meta,
        type => 'single',
      );
    }
    # BEFORE/AFTER/ABOUT YYYY
    if ($txt =~ /^(BEF|AFT|ABT)\s+(\d{4})/i) {
      my %mod = (BEF => 2, AFT => 3, ABT => 1);    # match your enum map
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        year     => $2 +0,
        modifier => $mod{ uc $1 } // 0,
        %$meta,
        type => 'single',
      );
    }
    # BETWEEN YYYY AND YYYY  (span)
    if ($txt =~ /BET\s+(\d{4})\s+AND\s+(\d{4})/i) {
      my $a =
        App::Schierer::HPFan::Model::Gramps::GrampsDate->new(year => $1 +0);
      my $b =
        App::Schierer::HPFan::Model::Gramps::GrampsDate->new(year => $2 +0);
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        start => $a,
        end   => $b,
        type  => 'span',
        %$meta,
      );
    }
    return undef;
  }

}

1;
