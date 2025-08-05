use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Surname {
  use Carp;

  field $value      : param : reader;
  field $prefix     : param : reader = undef;
  field $prim       : param : reader = 0;
  field $derivation : param : reader = "Unknown";
  field $connector  : param : reader = undef;

  ADJUST {
    croak "surname value is required" unless defined $value;

    # Validate derivation types from DTD comment
    my %valid_derivations = map { $_ => 1 } qw(
      Unknown Inherited Given Taken Patronymic Matronymic Feudal
      Pseudonym Patrilineal Matrilineal Occupation Location
    );

    if ($derivation && !$valid_derivations{$derivation}) {
      croak "Invalid derivation type: '$derivation'";
    }
  }

  method to_string() {
    my @parts;

    push @parts, $prefix if $prefix;
    push @parts, $value;

    return join(" ", @parts);
  }
}

1;
