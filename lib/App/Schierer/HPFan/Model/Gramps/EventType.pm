use v5.42;
use utf8::all;
use experimental qw(class);
use Readonly;

class App::Schierer::HPFan::Model::Gramps::EventType :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,              # used for concat too
    'eq'       => \&eq_over,                # string cmp
    '=='       => \&num_over,               # numeric cmp
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;                        # allow Perl defaults for the rest

  field $_class : param //= undef;
  field $string : param : reader //= undef;
  field $value  : param : reader //= undef;
  field $value_to_string;

  ADJUST {
    Readonly::Hash my %tmp => {
      0  => $string,
      1  => 'Marriage',
      6  => 'Engagement',
      7  => 'Divorce',
      12 => 'Birth',
      13 => 'Death',
      26 => 'Education',
      27 => 'Elected',
      31 => 'Graduation',
      37 => 'Occupation',
      40 => 'Property',
      43 => 'Retirement',
    };
    $value_to_string = \%tmp;
  }

  method equality($other, $swap = 0) {
    if (ref($other) ne 'App::Schierer::HPFan::Model::Gramps::EventType') {

    }

    if ($other->value == 0) {
      return $string eq $other->string;
    }
    return $value == $other->value;
  }

  # Return a stable “label”: prefer custom string; else builtin; else BuiltIn(n)
  method label {
    return $string if defined($string) && length $string;    # custom
    return $value_to_string->{$value}
      if defined $value && exists $value_to_string->{$value};
    if (defined($value)) {
      $self->dev_guard(
        "Value is defined: $value, but no mapping exists for it!!!");
      return $value;
    }
    return 'Unknown';
  }

  method to_string { $self->label }

}
1;
__END__
