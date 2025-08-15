use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::DateHelper;
require App::Schierer::HPFan::Model::Gramps::Object::Reference;
require App::Schierer::HPFan::Model::Gramps::Source::Reference;


class App::Schierer::HPFan::Model::Gramps::Citation :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  require App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id         : reader : param = undef;
  field $priv       : reader : param = undef;
  field $page       : reader : param = '';
  field $confidence : reader : param = 0;
  field $date       : param = undef;

  field $source_refs   : param //= [];
  field $obj_refs      : param //= [];
  field $srcattributes : param = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();


  method source_refs()     { [@$source_refs] }
  method obj_refs()     { [@$obj_refs] }
  method srcattributes() { [@$srcattributes] }


  method date {
    my $df = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    return $df->format_date($date);
  }

  method _import {
    $self->SUPER::_import;

    $confidence = $self->XPathContext->findvalue('./g:confidence',$self->XPathObject);
    $self->logger->logcroak(
      sprintf('confidence not discoverable in %s', $self->XPathObject))
      unless defined $confidence;
    $self->debug("confidence is $confidence");

    foreach my $ref (
      $self->XPathContext->findnodes('./g:sourceref', $self->XPathObject)) {
      push @$source_refs,
        App::Schierer::HPFan::Model::Gramps::Source::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }
    $self->logger->logcroak('at least one sourceref is required!!') unless(scalar @$source_refs);

    # optional things
    $id = $self->XPathObject->getAttribute('id');
    $priv = $self->XPathObject->getAttribute('priv');
    $date  = $dh->import_gramps_date($self->XPathObject, $self->XPathContext);
    $page = $self->XPathContext->findvalue('./g:page',$self->XPathObject);


    foreach my $ref (
      $self->XPathContext->findnodes('./g:objref', $self->XPathObject)) {
      push @$obj_refs,
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
