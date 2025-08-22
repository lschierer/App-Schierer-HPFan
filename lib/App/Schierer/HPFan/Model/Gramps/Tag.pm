use v5.42;
use utf8::all;
use experimental qw(class);
require JSON::PP;
require Data::Printer;

class App::Schierer::HPFan::Model::Gramps::Tag :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $_class    : param //= undef;
  field $name      : param //= undef;
  field $color     : param //= undef;
  field $priority  : param //= undef;

  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw( handle name color priority change json_data) };

  method name      { $self->_get_field('name') }
  method color     { $self->_get_field('color') }

  method parse_json_data {
    my $hash = JSON::PP->new->decode($self->json_data);
    $self->logger->debug(sprintf(
      'hash for tag "%s" is: %s',
      $self->handle, Data::Printer::np($hash),
    ));

  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{name}     = $name;
    $hr->{color}    = $color;
    $hr->{priority} = $priority;
    return $hr;
  }

}

1;
