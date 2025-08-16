use v5.42;
use utf8::all;
use experimental qw(class);
require JSON::PP;

class App::Schierer::HPFan::Model::Gramps::Person :
  isa( App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::Name;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;

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

  method id {
      my $result = $self->dbh->selectrow_hashref(
          "SELECT gramps_id FROM person WHERE handle = ?",
          undef,
          $self->handle
      );
      return $result ? $result->{gramps_id} : undef;
  }

  method gender {
      my $result = $self->dbh->selectrow_hashref(
          "SELECT gender FROM person WHERE handle = ?",
          undef,
          $self->handle
      );
      my %GENDER_MAP = (0 => 'F', 1 => 'M', 2 => 'U');
      if($result){
        return $GENDER_MAP{$result->{'gender'}} // 'U';
      }
      return 'U';
  }

  method private {
      my $result = $self->dbh->selectrow_hashref(
          "SELECT private FROM person WHERE handle = ?",
          undef,
          $self->handle
      );
      return $result->{'private'} if $result;
      return 0;
  }

  method change {
      my $result = $self->dbh->selectrow_hashref(
          "SELECT change FROM person WHERE handle = ?",
          undef,
          $self->handle
      );
      return $result ? $result->{change} : undef;
  }

  method parse_json_data {
    my $raw_json = $self->dbh->selectrow_hashref(
      "SELECT json_data FROM person WHERE handle = ?",
      undef,
      $self->handle
    );
    $raw_json = $raw_json->{'json_data'};
    $self->logger->debug("raw_json: '$raw_json'");
    #trust DBH::SQLite to have already handle UTF8.
    my $hash = JSON::PP->new->decode($raw_json);
    if(reftype($hash) eq 'HASH') {
      $self->logger->info("got hash ". Data::Printer::np($hash));
      return $hash;
    }else {
      $self->logger->error(sprintf('parsed json resulted in %s', reftype($hash)));
    }
    return {};
  }

  method names() {
    my @names;
    my $hash = $self->parse_json_data();
    if(exists $hash->{primary_name}) {
      my $name = App::Schierer::HPFan::Model::Gramps::Name->new(
        $hash->{primary_name}->%*
      );
      if($name){
        $name->set_alt(0);
        push @names, $name;
      }
    }
    if(exists $hash->{alternate_names} && scalar @{ $hash->{alternate_names} }){
      foreach my $nh ($hash->{alternate_names}->@*){
        my $name = App::Schierer::HPFan::Model::Gramps::Name->new(
          $nh->%*
        );
        if($name){
          $name->set_alt(1);
          push @names, $name;
        }
      }
    }
    $self->logger->debug(sprintf('there are %d names for %s',
    scalar @names, $self->handle));
    return \@names;
  }               # Return copy

  method event_refs()     {
    my $hash = $self->parse_json_data();
    return [];
  }

  method addresses()      {
  my $hash = $self->parse_json_data();
  return [];
  }
  method attributes()     { my $hash = $self->parse_json_data();
  return []; }
  method urls()           { my $hash = $self->parse_json_data();
  return []; }
  method child_of_refs()  { my $hash = $self->parse_json_data();
  return []; }
  method parent_in_refs() { my $hash = $self->parse_json_data();
  return []; }
  method person_refs()    { my $hash = $self->parse_json_data();
  return []; }
  method note_refs()      { my $hash = $self->parse_json_data();
  return []; }
  method citation_refs()  { my $hash = $self->parse_json_data();
  return []; }
  method tag_refs()       { my $hash = $self->parse_json_data();
  return []; }

  method primary_name() {
    # Return the first non-alternate name, or first name if all are alternate
    for my $name ($self->names->@*) {
      return $name unless $name->alt;
    }
    return scalar(@{$self->names}) ? $self->names->[0] : undef;
  }

  method get_surname() {
    my $last;
    my $name = $self->primary_name();
    $self->logger->debug(sprintf(
      'picked name "%s" as primary for "%s"', $name, $self->id));
    foreach my $sn (@{ $name->surnames }) {
      if ($sn->prim) {
        $last = $sn;
        last;
      }
    }
    if (not defined $last && scalar @{ $name->surnames }) {
      $last = $name->surnames->[0];
    }
    return $last;
  }

  method display_name() {
    my $name = $self->primary_name();
    unless ($name) {
      $self->warning("No name available for " . $self->handle);
      return " ";
    }
    $self->logger->debug(sprintf(
      'picked name "%s" as primary for "%s"', $name, $self->id));
    my $last;

    foreach my $sn (@{ $name->surnames }) {
      if ($sn->primary) {
        $last = $sn;
        last;
      }
    }
    if (not defined $last && scalar @{ $name->surnames }) {
      $last = $name->surnames->[0];
    }
    my $formatted = sprintf('%s %s %s %s',
      $name->display,
      $last->prefix ? $last->prefix : '',
      $last->surname  ? $last->surname  : 'Unknown',
      $name->suffix ? $name->suffix : '',
    );
    $formatted =~ s/^\s+|\s+$//g;
    $formatted =~ s/\s+/ /g;
    return $formatted;
  }

  method to_string() {
    my $primary  = $self->primary_name;
    my $name_str = $primary ? $primary->to_string : "Unknown";
    return sprintf("Person[%s]: %s (%s)", $self->handle, $name_str, $self->gender);
  }

  method to_hash {
    return {
      id             => $self->id,
      handle         => $self->handle,
      priv           => $self->private,
      change         => $self->change,
      gender         => $self->gender,
      names          => $self->names,
      event_refs     => $event_refs,
      addresses      => $addresses,
      attributes     => $attributes,
      urls           => $urls,
      child_of_refs  => $child_of_refs,
      parent_in_refs => $parent_in_refs,
      person_refs    => $person_refs,
      note_refs      => $note_refs,
      citation_refs  => $citation_refs,
      tag_refs       => $tag_refs,
    };
  }
}

1;
