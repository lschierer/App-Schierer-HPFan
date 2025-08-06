use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Event :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id     : reader : param = undef;
  field $handle : reader : param;
  field $priv   : reader : param = 0;
  field $change : reader : param;
  field $type   : reader : param = undef;
  field $date   : reader : param =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $place_ref     : reader : param = undef;    # handle reference to place
  field $cause         : reader : param = undef;
  field $description   : reader : param = undef;
  field $attributes    : param = [];                # unused, for future growth
  field $note_refs     : param = [];
  field $citation_refs : param = [];
  field $obj_refs      : param = [];
  field $tag_refs      : param = [];

  ADJUST {
    croak "handle is required"           unless defined $handle;
    croak "change timestamp is required" unless defined $change;
  }

  method attributes()    { [@$attributes] }
  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }
  method obj_refs()      { [@$obj_refs] }
  method tag_refs()      { [@$tag_refs] }

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
    return sprintf("Event[%s]: %s", $handle, $desc);
  }

  method to_hash {
    return {
      id            => $id,
      handle        => $handle,
      change        => $change,
      type          => $type,
      date          => $date,
      place_ref     => $place_ref,
      cause         => $cause,
      description   => $description,
      attributes    => [$attributes->@*],
      note_refs     => [$note_refs->@*],
      citation_refs => [$citation_refs->@*],
      obj_refs      => [$obj_refs->@*],
      tag_refs      => [$tag_refs->@*],
    };
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
