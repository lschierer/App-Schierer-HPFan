use v5.42;
use utf8::all;
use experimental qw(class);
require JSON::PP;
require Data::Printer;

class App::Schierer::HPFan::Model::Gramps::Tag :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;

  field $data :param;

  field $handle : reader //= undef;
  field $name   : reader //= undef;

  ADJUST {
    $handle = $data->{handle};
    $name   = $data->{name};
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{name}     = $name;
    $hr->{handle}   = $handle;
    return $hr;
  }

}

1;
