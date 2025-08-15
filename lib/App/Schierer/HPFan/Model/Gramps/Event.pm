use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Citation::Reference;
require App::Schierer::HPFan::Model::Gramps::Note::Reference;
require App::Schierer::HPFan::Model::Gramps::Tag::Reference;
require App::Schierer::HPFan::Model::Gramps::Place::Reference;
require App::Schierer::HPFan::Model::Gramps::Object::Reference;

class App::Schierer::HPFan::Model::Gramps::Event :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id   : reader : param = undef;
  field $priv : reader : param = 0;
  field $type : reader : param = undef;
  field $date : reader : param =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $place_ref   : reader : param = undef;    # handle reference to place
  field $cause       : reader : param = undef;
  field $description : reader : param = undef;
  field $attributes  : param = [];                # unused, for future growth
  field $obj_refs    : param = [];

  method attributes() { [@$attributes] }
  method obj_refs()   { [@$obj_refs] }

  method date_string() {
    return undef unless $date;
    return App::Schierer::HPFan::Model::Gramps::DateHelper->format_date($date);
  }

  method _import {
    my $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    $self->SUPER::_import;
    $id = $self->XPathObject->getAttribute('id');
    $self->logger->logcroak(
      sprintf('id not discoverable in %s', $self->XPathObject))
      unless defined $id;
    $self->debug("id is $id");

    $type = $self->XPathContext->findvalue('./g:type', $self->XPathObject);
    $self->logger->logcroak(
      sprintf('type not discoverable in %s', $self->XPathObject))
      unless defined $type;
    $self->debug("type for $id is $type");

    #optional things
    $date  = $dh->import_gramps_date($self->XPathObject, $self->XPathContext);
    $priv  = $self->XPathObject->getAttribute('priv');
    $cause = $self->XPathContext->findvalue('./g:cause');
    $description = $self->XPathContext->findvalue('./g:description') // ' ';
    $place_ref   = App::Schierer::HPFan::Model::Gramps::Place::Reference->new(
      XPathContext => $self->XPathContext,
      XPathObject  =>
        $self->XPathContext->findvalue('./g:place', $self->XPathObject)
    );

    foreach my $ref ($self->XPathContext->findnodes('./g:objref')) {
      push @$obj_refs,
        App::Schierer::HPFan::Model::Gramps::Object::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }

  }

  method to_string() {
    my @parts;

    push @parts, $type if $type;

    if (my $date_str = $self->date_string) {
      push @parts, "($date_str)";
    }

    push @parts, $description if $description;

    my $desc = @parts ? join(" ", @parts) : "Unknown event";
    return sprintf("Event[%s]: %s", $self->handle, $desc);
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{id}   = $id;
    $hr->{type} = $type;
    $hr->{date} =
      App::Schierer::HPFan::Model::Gramps::DateHelper->format_date($date);
    $hr->{place_ref}   = $place_ref;
    $hr->{cause}       = $cause;
    $hr->{description} = $description;
    $hr->{attributes}  = [$attributes->@*];
    $hr->{obj_refs}    = [$obj_refs->@*];

    return $hr;
  }

  method TO_JSON {
    my $json =
      JSON::PP->new->utf8->pretty->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}

1;
