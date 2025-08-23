use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require Scalar::Util;
require App::Schierer::HPFan::Model::Gramps::Tag;
require App::Schierer::HPFan::View::Markdown;

class App::Schierer::HPFan::Model::Gramps::Note::Text :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use Readonly;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,              # string equality
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  ADJUST {
    my @names;
    push @names, keys $self->ALLOWED_FIELD_NAMES->%*;
    foreach my $tn (@names) {
      $self->ALLOWED_FIELD_NAMES->{$tn} = undef;
    }

  }

  field $_class : param //= undef;
  field $string : param //= undef;
  field $tags   : param //= [];

  ADJUST {
    if (defined $string) {
      $string =~ s/^\s+|\s+$//g;
    }
  }

  method tags { [$tags->@*] }

  method _comparison ($other, $swap = 0) {
    return $self->to_string cmp $other->to_string;
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method to_hash {
    return {} if $self->private;
    my $r = { ref => $self->ref };
    $r->{'string'} = $string if defined($string);
    $r->{'tags'}   = $tags   if scalar(@{$tags});
    return $r;
  }

  method raw {
    return $string unless not defined $string;
    return '';
  }

  method to_string {
    if ($_class eq 'StyledText') {
      my $md = App::Schierer::HPFan::View::Markdown->new();
      return $md->format_string($string) unless not defined($string);
      return '';
    }
    else {
      return $string unless not defined $string;
      return '';
    }
  }
}
1;
__END__
SELECT
    gramps_id,
    json_extract(json_data, '$.type.value')   AS type_value,
FROM note
ORDER BY type_value, type_string, gramps_id;
