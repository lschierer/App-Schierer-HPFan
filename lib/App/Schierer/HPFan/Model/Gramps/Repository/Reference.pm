use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Repository::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  field $medium : param : reader = undef;

  method _import {
    $self->SUPER::_import;
    $medium = $self->XPathObject->getAttribute('medium');
    $self->logger->logcroak(
      sprintf('medium not discoverable in %s', $self->XPathObject))
      unless defined $medium;
  }
}
1;
__END__
