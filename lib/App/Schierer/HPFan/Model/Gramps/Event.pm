use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Note::Reference;
require App::Schierer::HPFan::Model::Gramps::Place::Reference;
require App::Schierer::HPFan::Model::Gramps::Object::Reference;
require App::Schierer::HPFan::Model::Gramps::EventType;

class App::Schierer::HPFan::Model::Gramps::Event :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;
  use overload
    '<=>'      => \&_comparison,
    'eq'       => \&_equality,
    'ne'       => \&_inequality,
    '""'       => \&to_string,
    'fallback' => 0;

  field $description : param = undef;
  field $gramps_id   : param = undef;
  field $json_data   : param = undef;
  field $place       : param = undef;

  field $type : reader = undef;
  field $date : reader =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $place_ref : reader = undef;    # handle reference to place
  field $cause     : reader = undef;
  field $attributes = [];               # unused, for future growth
  field $obj_refs   = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

  ADJUST {
    my $hash = $self->parse_json_data;
  }

  field $ALLOWED_FIELD_NAMES : reader = { map { $_ => 1 }
      qw( gramps_id description place change private json_data) };

  method gramps_id   { $self->_get_field('gramps_id') }
  method description { $self->_get_field('description') }
  method place       { $self->_get_field('place') }
  method change      { $self->_get_field('change') }
  method private     { $self->_get_field('private') // 0; }

  method json_data {
    $json_data = $self->_get_field('json_data');
    return $json_data ? $json_data : {};
  }

  method parse_json_data {
    my $hash = JSON::PP->new->decode($json_data);
    if (reftype($hash) eq 'HASH') {
      $self->logger->info("got event hash " . Data::Printer::np($hash));

      # set the things that come from the JSON only.
      $type = App::Schierer::HPFan::Model::Gramps::EventType->new(
        $hash->{'type'}->%*);
      $date = $dh->parse($hash->{'date'});
      $self->logger->debug("found date " . Data::Printer::np($date));
      foreach my $eventref ($hash->{event_ref_list}->%*) {

      }
    }
    else {
      $self->logger->error(
        sprintf('parsed event json resulted in %s', reftype($hash)));
    }
    return {};
  }

  method attributes() { [@$attributes] }
  method obj_refs()   { [@$obj_refs] }

  method to_string() {
    my @parts;

    push @parts, $type if $type;

    if (my $date_str = $date->to_string) {
      push @parts, "($date_str)";
    }

    push @parts, $description if $description;

    my $desc = @parts ? join(" ", @parts) : "Unknown event";
    return sprintf("Event[%s]: %s", $self->handle, $desc);
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{id}          = $gramps_id;
    $hr->{type}        = $type;
    $hr->{date}        = $date->to_string;
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
