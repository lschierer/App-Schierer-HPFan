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

  field $description  : reader : param = undef;
  field $gramps_id    : reader : param = undef;
  field $json_data    : param = undef;
  field $place        : reader : param = undef;
  field $private      : reader : param = 0;

  field $type : reader = undef;
  field $date : reader  =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $place_ref   : reader  = undef;    # handle reference to place
  field $cause       : reader  = undef;
  field $attributes  = [];                # unused, for future growth
  field $obj_refs    = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
  method attributes() { [@$attributes] }
  method obj_refs()   { [@$obj_refs] }

  method date_string() {
    return undef unless $date;
    return App::Schierer::HPFan::Model::Gramps::DateHelper->format_date($date);
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
    $hr->{id}   = $gramps_id;
    $hr->{type} = $type;
    $hr->{date} = $dh->format_date($date);
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
