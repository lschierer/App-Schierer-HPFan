use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference;
require App::Schierer::HPFan::Model::Gramps::Person::Reference;

class App::Schierer::HPFan::Model::Gramps::Person :
  isa( App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::Name;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $given_name      : param = undef;
  field $surname         : param = undef;
  field $gramps_id       : param = undef;
  field $gender          : param = 'U';
  field $death_ref_index : param = undef;
  field $birth_ref_index : param = undef;
  field $json_data       : param = undef;

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

  field $ALLOWED_FIELD_NAMES : reader = {
    map { $_ => 1 }
      qw(given_name
      surname
      gramps_id
      gender
      death_ref_index
      birth_ref_index
      private
      json_data        )
  };

  method given_name      { $self->_get_field('given_name') }
  method surname         { $self->_get_field('surname') }
  method gramps_id       { $self->_get_field('gramps_id') }
  method death_ref_index { $self->_get_field('death_ref_index') }
  method birth_ref_index { $self->_get_field('birth_ref_index') }
  method private         { $self->_get_field('private') }
  method json_data       { $self->_get_field('json_data') }

  method gender {
    my $gv         = $self->_get_field('gender');
    my %GENDER_MAP = (0 => 'F', 1 => 'M', 2 => 'U');
    if ($gv) {
      return $GENDER_MAP{$gv} // 'U';
    }
    return 'U';
  }

  method id { $self->gramps_id }

  method parse_json_data {
    my $raw_json = $self->json_data;
    $self->logger->debug("raw_json: '$raw_json'");
    #trust DBH::SQLite to have already handle UTF8.
    my $hash = JSON::PP->new->decode($raw_json);
    if (reftype($hash) eq 'HASH') {
      $self->logger->info("got hash " . Data::Printer::np($hash));

      foreach my $er ($hash->{'event_ref_list'}->@*) {
        push @$event_refs,
          App::Schierer::HPFan::Model::Gramps::Event::Reference->new($er->%*);
      }

      foreach my $item ($hash->{'family_list'}->@*) {
        push @$parent_in_refs, $item;
      }

      foreach my $item ($hash->{'note_list'}->@*) {
        push @$note_refs, $item;
      }

      foreach my $item ($hash->{'parent_family_list'}->@*) {
        push @$child_of_refs, $item;
      }

      foreach my $item ($hash->{'note_list'}->@*) {
        push @$note_refs, $item;
      }

      foreach my $item ($hash->{'tag_list'}->@*) {
        push @$tag_refs, $item;
      }

      foreach my $item ($hash->{'person_ref_list'}->@*) {
        push @$person_refs,
          App::Schierer::HPFan::Model::Gramps::Person::Reference->new(
          $item->%*);
      }

    }
    else {
      $self->logger->error(
        sprintf('parsed json resulted in %s', reftype($hash)));
    }
    return {};
  }

  method names() {
    my @names;
    my $hash = JSON::PP->new->decode($self->json_data);
    if (exists $hash->{primary_name}) {
      my $name = App::Schierer::HPFan::Model::Gramps::Name->new(
        $hash->{primary_name}->%*);
      if ($name) {
        $name->set_alt(0);
        push @names, $name;
      }
    }
    if (exists $hash->{alternate_names} && scalar @{ $hash->{alternate_names} })
    {
      foreach my $nh ($hash->{alternate_names}->@*) {
        my $name = App::Schierer::HPFan::Model::Gramps::Name->new($nh->%*);
        if ($name) {
          $name->set_alt(1);
          push @names, $name;
        }
      }
    }
    $self->logger->debug(sprintf(
      'there are %d names for %s', scalar @names, $self->handle));
    return \@names;
  }    # Return copy

  method event_refs() {
    my $hash   = JSON::PP->new->decode($self->json_data);
    my $result = [];
    foreach my $er ($hash->{'event_ref_list'}->@*) {
      push @$result,
        App::Schierer::HPFan::Model::Gramps::Event::Reference->new($er->%*);
    }
    return [$result->@*];
  }

  method addresses() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return $hash->{'address_list'};
  }

  method attributes() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return $hash->{'attribute_list'};
  }

  method urls() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return $hash->{'urls'};
  }

  method child_of_refs() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return $hash->{'parent_family_list'};
  }

  method parent_in_refs() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return $hash->{'family_list'};
  }

  method person_refs() {
    my $hash   = JSON::PP->new->decode($self->json_data);
    my $result = [];
    foreach my $item ($hash->{'person_ref_list'}->@*) {
      push @$result,
        App::Schierer::HPFan::Model::Gramps::Person::Reference->new($item->%*);
    }
    return [$result->@*];
  }

  method note_refs() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return [];
  }

  method citation_refs() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return [$hash->{'note_list'}->@*];
  }

  method tag_refs() {
    my $hash = JSON::PP->new->decode($self->json_data);
    return [$hash->{'tag_list'}->@*];
  }

  method primary_name() {
    # Return the first non-alternate name, or first name if all are alternate
    for my $name ($self->names->@*) {
      return $name unless $name->alt;
    }
    return scalar(@{ $self->names }) ? $self->names->[0] : undef;
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
      $last->prefix  ? $last->prefix  : '',
      $last->surname ? $last->surname : 'Unknown',
      $name->suffix  ? $name->suffix  : '',
    );
    $formatted =~ s/^\s+|\s+$//g;
    $formatted =~ s/\s+/ /g;
    return $formatted;
  }

  method to_string() {
    my $primary  = $self->primary_name;
    my $name_str = $primary ? $primary->to_string : "Unknown";
    return
      sprintf("Person[%s]: %s (%s)", $self->handle, $name_str, $self->gender);
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
