use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Object::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  field $priv : reader : param //= undef;

  ADJUST {
    $self->region_attribute_optional      = 1;
    $self->attribute_attribute_optional   = 1;
    $self->citationref_attribute_optional = 1;
    $self->noteref_attribute_optional     = 1;
  }

  method _import {
    $self->SUPER::_import;
    $priv = $self->XPathObject->getAttribute('priv');
    $self->logger->logcroak(
      sprintf('priv not discoverable in %s', $self->XPathObject))
      unless defined $priv;
  }

}
1;
__END__
