use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference;
require App::Schierer::HPFan::Model::Gramps::Name;

class App::Schierer::HPFan::Model::Gramps::Person :
  isa( App::Schierer::HPFan::Logger) {
  use Carp;
  use List::AllUtils qw( any );
  use App::Schierer::HPFan::Model::Gramps::Name;

  field $data : param //= undef;

  field $birth_ref_index : reader //= undef;
  field $death_ref_index : reader //= undef;
  field $gender          : reader //= 'U';
  field $given_name //= undef;
  field $gramps_id    : reader //= undef;
  field $handle       : reader //= undef;
  field $primary_name : reader //= undef;
  field $surname //= undef;

  field $addresses          = [];
  field $alternate_names    = [];
  field $attributes         = [];
  field $citation_list      = [];
  field $event_ref_list     = [];
  field $family_list        = [];
  field $note_list          = [];
  field $parent_family_list = [];
  field $person_refs        = [];
  field $tag_list           = [];
  field $urls               = [];

  method event_ref_list     { [@$event_ref_list] }
  method addresses          { [@$addresses] }
  method attributes         { [@$attributes] }
  method urls               { [@$urls] }
  method family_list        { [@$family_list] }
  method parent_family_list { [@$parent_family_list] }
  method person_refs        { [@$person_refs] }
  method note_list          { [@$note_list] }
  method citation_list      { [@$citation_list] }
  method tag_list           { [@$tag_list] }

  ADJUST {
    $birth_ref_index =
      (defined($data) and exists $data->{birth_ref_index})
      ? $data->{birth_ref_index}
      : undef;
    $death_ref_index = $data->{death_ref_index};
    $gender    = $data->{gender} == 1 ? 'M' : $data->{gender} == 0 ? 'F' : 'U';
    $gramps_id = $data->{gramps_id};
    $handle    = $data->{handle};
    $primary_name = App::Schierer::HPFan::Model::Gramps::Name->new(
      data => $data->{primary_name});

    foreach my $item ($data->{alternate_names}->@*) {
      App::Schierer::HPFan::Model::Gramps::Name->new(data => $item);
    }

    foreach my $item ($data->{citation_list}->@*) {
      push @$citation_list, $item;
    }

    foreach my $item ($data->{event_ref_list}->@*) {
      push @$event_ref_list,
        App::Schierer::HPFan::Model::Gramps::Event::Reference->new(
        data => $item);
    }

    foreach my $item ($data->{family_list}->@*) {
      push @$family_list, $item;
    }

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

    foreach my $item ($data->{parent_family_list}->@*) {
      push @$parent_family_list, $item;
    }

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }

  }

  method names() {
    my @names;
    push @names, $primary_name, push @names, $alternate_names->@*;
    return \@names;
  }

  method get_surname() {
    my $last;
    my $name = $primary_name;
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
    my $name = $primary_name;
    unless ($name) {
      $self->warning("No name available for " . $self->handle);
      return " ";
    }
    $self->logger->debug(sprintf(
      'picked name "%s" as primary for "%s"', $name, $gramps_id));
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
    my $primary  = $primary_name;
    my $name_str = $primary ? $primary->to_string : "Unknown";
    return
      sprintf("Person[%s]: %s (%s)", $self->handle, $name_str, $self->gender);
  }

  method to_hash {
    return {
      id          => $gramps_id,
      handle      => $handle,
      gender      => $gender,
      names       => $self->names,
      events      => $event_ref_list,
      addresses   => $addresses,
      attributes  => $attributes,
      urls        => $urls,
      child_of    => $parent_family_list,
      family_list => $family_list,
      persons     => $person_refs,
      notes       => $note_list,
      citations   => $citation_list,
      tags        => $tag_list,
    };
  }
}

1;
