use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Style;

class App::Schierer::HPFan::Model::Gramps::Note :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $id     : reader : param = undef;
  field $priv   : reader : param = 0;
  field $format : reader : param = undef;
  field $type   : reader : param = undef;
  field $text   : reader : param = ' ';

  field $styles : param = [];

  method styles { [$styles->@*] }

  method _import {
    $self->SUPER::_import;

    $id = $self->XPathObject->getAttribute('id');
    $self->logger->logcroak(
      sprintf('id not discoverable in %s', $self->XPathObject))
      unless defined $id;
    $self->debug("id is $id");

    # optional things
    $priv = $self->XPathObject->getAttribute('priv');
    $format = $self->XPathObject->getAttribute('format');
    $type = $self->XPathObject->getAttribute('type');
    $text = $self->XPathContext->findvalue('./g:text', $self->XPathObject);

    foreach my $s ($self->XPathContext->findnodes('./g:style', $self->XPathObject)) {
      push @$styles, App::Schierer::HPFan::Model::Gramps::Style->new(
        XPathContext  => $self->XPathContext,
        XPathObject   => $self->XPathObject,
      );
    }
  }

}
1;
__END__
