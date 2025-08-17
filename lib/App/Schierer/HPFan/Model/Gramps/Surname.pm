use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Surname :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    '.'        => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'cmp'      => \&_equality,
    'fallback' => 0;

  field $_class     : param;
  field $connector  : param : reader = undef;
  field $origintype : param;
  field $prefix     : param : reader = undef;
  field $primary    : param : reader = 0;
  field $surname    : param : reader //= undef;

  field $derivation : param : reader = "Unknown";

  ADJUST {
    # Validate derivation types from DTD comment
    my %valid_derivations = map { $_ => 1 } qw(
      Unknown Inherited Given Taken Patronymic Matronymic Feudal
      Pseudonym Patrilineal Matrilineal Occupation Location
    );
    $derivation = $origintype->{'string'}
      && length($origintype->{'string'}) ? $origintype->{'string'} : undef;
    if ($derivation && !$valid_derivations{$derivation}) {
      $self->logger->logcroak("Invalid derivation type: '$derivation'");
    }
  }

  method display_name {
    my @parts;
    push @parts, $prefix    if $prefix;
    push @parts, $connector if $connector;
    push @parts, $surname;
    return join(' ', @parts);
  }

  method _equality ($other, $swap = 0) {
    return $self->display_name cmp $other->display_name;
  }

  method to_string() {
    my @parts;

    push @parts, $prefix if $prefix;
    push @parts, $surname;

    return join(" ", @parts);
  }
}

1;
