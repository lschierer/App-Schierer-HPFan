use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::GrampsDate;

class App::Schierer::HPFan::Model::Gramps::DateHelper :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Scalar::Util qw(looks_like_number);

  #------------ internal helpers ------------#

  # Build a single-date GrampsDate from a slice of dateval starting at $off
  method _single_from_dateval ($h, $off = 0, $inherit_meta = 0) {
    my $dv = $h->{dateval} // [];
    my ($d, $m, $y) = map { $dv->[$_] } ($off +0, $off + 1, $off + 2);

    my %base = (
      year  => ($y // 0) +0,
      month => ($m // 0) +0,
      day   => ($d // 0) +0,
      type  => 'single',
    );

# keep calendar on children (harmless/useful), but NOT modifier/quality/text/sortval
    $base{calendar} = $h->{calendar} // 0;

    # only for true single, if you ever want it:
    if ($inherit_meta) {
      $base{modifier} = $h->{modifier} // 0;
      $base{newyear}  = $h->{newyear}  // 0;
      $base{quality}  = $h->{quality}  // 0;
      $base{sortval}  = $h->{sortval}  // 0;
      $base{text}     = $h->{text}     // '';
    }

    return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(%base);
  }

  method _has_any_end ($h) {
    my $dv = $h->{dateval} // [];
    return 0 if ref($dv) ne 'ARRAY' || @$dv < 7;
    # consider non-zero / defined as "present"
    return !!(($dv->[4] // 0) || ($dv->[5] // 0) || ($dv->[6] // 0));
  }

  #------------ public API ------------#

  # Small parser for common textual forms; aligns with your enum mapping
  method _from_free_text ($txt, $meta) {
    my %mod = (BEF => 1, AFT => 2, ABT => 3);    # your mapping

    # EXACT YYYY[-MM[-DD]]
    if ($txt =~ /\b(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?\b/) {
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        year  => $1 +0,
        month => ($2 // 0) +0,
        day   => ($3 // 0) +0,
        %$meta,
        type => 'single',
      );
    }

    # BEFORE/AFTER/ABOUT YYYY
    if ($txt =~ /^(BEF|AFT|ABT)\s+(\d{4})(?!\S)/i) {
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        year     => $2 +0,
        modifier => $mod{ uc $1 } // 0,
        %$meta,
        type => 'single',
      );
    }

    # BETWEEN yyyy[-mm[-dd]] AND yyyy[-mm[-dd]]
    if ($txt =~
/BET(?:WEEN)?\s+(\d{4}(?:-\d{1,2}(?:-\d{1,2})?)?)\s+AND\s+(\d{4}(?:-\d{1,2}(?:-\d{1,2})?)?)/i
    ) {
      my ($a, $b) = ($1, $2);
      my $sa = _parse_iso_like($a);
      my $sb = _parse_iso_like($b);
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        start => App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
          %$sa, type => 'single'
        ),
        end => App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
          %$sb, type => 'single'
        ),
        modifier => 4,    # between
        %$meta,
        type => 'span',
      );
    }

    # FROM yyyy[-..] [TO yyyy[-..]]
    if ($txt =~
/^FROM\s+(\d{4}(?:-\d{1,2}(?:-\d{1,2})?)?)(?:\s+TO\s+(\d{4}(?:-\d{1,2}(?:-\d{1,2})?)?))?/i
    ) {
      my $sa = _parse_iso_like($1);
      my $ea = $2 ? _parse_iso_like($2) : undef;
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        start => App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
          %$sa, type => 'single'
        ),
        (
          $ea
          ? (
            end => App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
              %$ea, type => 'single'
            )
            )
          : ()
        ),
        modifier => 5,    # from
        %$meta,
        type => ($ea ? 'range' : 'range')
        ,                 # treat open-ended as range with only start
      );
    }

    return undef;

    sub _parse_iso_like ($s) {
      my ($y, $m, $d) = split /-/, $s, 3;
      return +{
        year  => ($y // 0) +0,
        month => ($m // 0) +0,
        day   => ($d // 0) +0,
      };
    }
  }

  method parse ($h) {
    return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
      type => 'single')
      unless $h && ref($h) eq 'HASH';

    if (exists $h->{dateval} && ref($h->{dateval}) eq 'ARRAY') {
      if ($self->_has_any_end($h)) {
        my $start    = $self->_single_from_dateval($h, 0, 0);
        my $end      = $self->_single_from_dateval($h, 4, 0);
        my $modifier = $h->{modifier} // 0;
        my $type     = ($modifier == 4) ? 'span' : 'range';
        return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
          start    => $start,
          end      => $end,
          calendar => $h->{calendar} // 0,
          modifier => $modifier,
          newyear  => $h->{newyear} // 0,
          quality  => $h->{quality} // 0,
          sortval  => $h->{sortval} // 0,
          text     => $h->{text}    // '',
          type     => $type,
        );
      }
      return $self->_single_from_dateval($h, 0, 1);
    }

    if (($h->{type} // '') =~ /^(?:range|span)$/i || $h->{start} || $h->{end}) {
      my $start    = $h->{start} ? $self->parse($h->{start}) : undef;
      my $end      = $h->{end}   ? $self->parse($h->{end})   : undef;
      my $modifier = $h->{modifier} // 0;
      my $type     = ($modifier == 4) ? 'span' : lc($h->{type} // 'range');
      return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
        start    => $start,
        end      => $end,
        calendar => $h->{calendar} // 0,
        modifier => $modifier,
        newyear  => $h->{newyear} // 0,
        quality  => $h->{quality} // 0,
        sortval  => $h->{sortval} // 0,
        text     => $h->{text}    // '',
        type     => $type,
      );
    }

    # ✅ FREE-TEXT FALLBACK (this was missing)
    if (defined $h->{text} && length $h->{text}) {
      (my $txt = $h->{text}) =~ s/^\s+|\s+$//g;
      my $gd = $self->_from_free_text($txt, $h);
      return $gd if $gd;
    }

    # final fallback
    return App::Schierer::HPFan::Model::Gramps::GrampsDate->new(
      type => 'single');
  }

}
1;
