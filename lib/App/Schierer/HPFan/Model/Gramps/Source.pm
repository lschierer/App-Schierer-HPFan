use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Source :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  require App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id            : reader : param = undef;
  field $stitle        : reader : param = undef;
  field $sauthor       : reader : param = undef;
  field $spubinfo      : reader : param = undef;
  field $sabbrev       : reader : param = undef;
  field $repo_refs     : param = [];
  field $obj_refs      : param = [];
  field $srcattributes : param = [];

  method repo_refs()     { [@$repo_refs] }
  method obj_refs()      { [@$obj_refs] }
  method srcattributes() { [@$srcattributes] }

  method _import {
    $self->SUPER::_import;

    $id = $self->XPathObject->getAttribute('id');
    $self->logger->logcroak(
      sprintf('id not discoverable in %s', $self->XPathObject))
      unless defined $id;
    $self->debug("id is $id");

    $stitle = $self->XPathContext->findvalue('./g:stitle', $self->XPathObject);
    $self->logger->logcroak(
      sprintf('stitle not discoverable in %s', $self->XPathObject))
      unless defined $stitle;
    $self->debug("stitle is $stitle");

    # optional things
    $sauthor =
      $self->XPathContext->findvalue('./g:sauthor', $self->XPathObject);
    $spubinfo =
      $self->XPathContext->findvalue('./g:spubinfo', $self->XPathObject);
    $sabbrev =
      $self->XPathContext->findvalue('./g:sabbrev', $self->XPathObject);

    foreach my $ref ($self->XPathContext->findnodes('./g:objref')) {
      push @$obj_refs,
        App::Schierer::HPFan::Model::Gramps::Object::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }

    foreach my $ref ($self->XPathContext->findnodes('./g:reporef')) {
      push @$repo_refs,
        App::Schierer::HPFan::Model::Gramps::Object::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }

    foreach my $srcattr ($self->XPathContext->findnodes('./g:srcattribute')) {
      my $sp     = $srcattr->getAttribute('priv');
      my $skey   = $srcattr->getAttribute('key');
      my $svalue = $srcattr->getAttribute('value');
      push @$srcattributes,
        {
        priv  => $sp,
        key   => $skey,
        value => $svalue,
        };
    }
  }
}
1;
__END__
