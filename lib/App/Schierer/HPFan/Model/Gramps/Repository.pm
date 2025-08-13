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
  field $url   : param  //= [];

  method url { [@$url] }

  method _import {
    $self->SUPER::_import;

    $id = $self->XPathObject->getAttribute('id');
    $self->logger->logcroak(
      sprintf('id not discoverable in %s', $self->XPathObject))
      unless defined $id;
    $self->debug("id is $id");

    # optional things
    $type  = $self->XPathContext->findvalue('./g:type',  $self->XPathObject);
    $rname = $self->XPathContext->findvalue('./g:rname', $self->XPathObject);
    foreach my $xu ( $self->XPathContext->findnodes('./g:url', $self->XPathObject)){
      push @$url, App::Schierer::HPFan::Model::Gramps::Url->new(
        XPathContext  => $self->XPathContext,
        XPathObject   => $xu,
      );
    }

  }
}
1;
__END__
