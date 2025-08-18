use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Url;

class App::Schierer::HPFan::Model::Gramps::Repository :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $id    : param : reader = undef;
  field $rname : param : reader = undef;
  field $type  : param : reader = undef;
  field $url   : param //= [];

  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw( gramps_id change private json_data) };

  method url { [@$url] }

  method _import {
    $self->SUPER::_import;

    $type = $self->XPathContext->findvalue('./g:type', $self->XPathObject);
    $self->logger->logcroak(
      sprintf('type not discoverable in %s', $self->XPathObject))
      unless defined $type;
    $self->logger->debug("type is $type");

    $rname = $self->XPathContext->findvalue('./g:rname', $self->XPathObject);
    $self->logger->logcroak(
      sprintf('rname not discoverable in %s', $self->XPathObject))
      unless defined $rname;
    $self->logger->debug("rname is $rname");

    # optional things
    $id = $self->XPathObject->getAttribute('id');

    foreach
      my $xu ($self->XPathContext->findnodes('./g:url', $self->XPathObject)) {
      push @$url,
        App::Schierer::HPFan::Model::Gramps::Url->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $xu,
        );
    }

  }
}
1;
__END__
