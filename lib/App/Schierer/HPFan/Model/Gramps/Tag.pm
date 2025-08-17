use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Tag :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $name     : reader : param //= undef;
  field $color    : reader : param //= undef;
  field $priority : reader : param //= undef;

  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw( gramps_id change private json_data) };

  method _import {
    $self->SUPER::_import;
    $name     = $self->XPathObject->getAttribute('name');
    $color    = $self->XPathObject->getAttribute('color');
    $priority = $self->XPathObject->getAttribute('priority');
    $self->logger->logcroak(
      sprintf('name not discoverable in %s', $self->XPathObject))
      unless defined $name;
    $self->logger->logcroak(
      sprintf('color not discoverable in %s', $self->XPathObject))
      unless defined $color;
    $self->logger->logcroak(
      sprintf('priority not discoverable in %s', $self->XPathObject))
      unless defined $priority;

    if ($color && $color !~ /^#[0-9A-Fa-f]{6}$/) {
      $self->fatal("color must be in hex format (#RRGGBB): $color");
    }

    # Validate priority is numeric
    if ($priority && $priority !~ /^\d+$/) {
      $self->fatal("priority must be numeric: $priority");
    }
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
