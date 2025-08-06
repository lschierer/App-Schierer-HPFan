use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Person :
  isa( App::Schierer::HPFan::Logger) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::Name;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id             : param : reader = undef;
  field $handle         : param : reader;
  field $priv           : param : reader = 0;
  field $change         : param : reader;
  field $gender         : param : reader;
  field $names          : param = [];
  field $event_refs     : param = [];
  field $addresses      : param = [];
  field $attributes     : param = [];
  field $urls           : param = [];
  field $child_of_refs  : param = [];
  field $parent_in_refs : param = [];
  field $person_refs    : param = [];
  field $note_refs      : param = [];
  field $citation_refs  : param = [];
  field $tag_refs       : param = [];

  ADJUST {
    $self->logger->logcroak("handle is required") unless defined $handle;
    $self->logger->logcroak("change timestamp is required")
      unless defined $change;
    $self->logger->logcroak("gender is required") unless defined $gender;
    $self->logger->logcroak("gender must be M, F, or U")
      unless $gender =~ /^[MFU]$/;

    # Validate that names is an array of Name objects
    if (@$names) {
      for my $name (@$names) {
        $self->logger->logcroak("names must be Name objects")
          unless ref($name) eq 'App::Schierer::HPFan::Model::Gramps::Name';
      }
    }
  }

  method names()          { [@$names] }               # Return copy
  method event_refs()     { [@$event_refs] }
  method addresses()      { [@$addresses] }
  method attributes()     { [@$attributes] }
  method urls()           { [@$urls] }
  method child_of_refs()  { [@$child_of_refs] }
  method parent_in_refs() { [$parent_in_refs->@*] }
  method person_refs()    { [@$person_refs] }
  method note_refs()      { [@$note_refs] }
  method citation_refs()  { [@$citation_refs] }
  method tag_refs()       { [@$tag_refs] }

  method primary_name() {
    # Return the first non-alternate name, or first name if all are alternate
    for my $name (@$names) {
      return $name unless $name->alt;
    }
    return @$names ? $names->[0] : undef;
  }

  method display_name() {
    my $name = $self->primary_name();
    $self->logger->debug(sprintf(
      'picked name "%s" as primary for "%s"', $name, $self->id));
    my $last;
    foreach my $sn (@{ $name->surnames }) {
      if ($sn->prim) {
        $last = $sn;
        last;
      }
    }
    if (not defined $last && scalar @{ $name->surnames }) {
      $last = $name->surnames->[0];
    }
    return sprintf('%s %s %s %s',
      $name->display,
      $last->prefix ? $last->prefix : '',
      $last->value  ? $last->value  : 'Unknown',
      $name->suffix ? $name->suffix : '',
    );
  }

  method to_string() {
    my $primary  = $self->primary_name;
    my $name_str = $primary ? $primary->to_string : "Unknown";
    return sprintf("Person[%s]: %s (%s)", $handle, $name_str, $gender);
  }
}

1;
