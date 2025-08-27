use v5.42;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference;
require App::Schierer::HPFan::Model::Gramps::Person::Child::Reference;
require App::Schierer::HPFan::Model::Gramps::Family::Relationship;

class App::Schierer::HPFan::Model::Gramps::Family :
  isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any );
  use Carp;

  field $data : param;

  field $complete      : reader = 0;
  field $father_handle : reader = undef;    # handle reference
  field $gramps_id     : reader = undef;
  field $handle        : reader = undef;
  field $mother_handle : reader = undef;
  field $private       : reader = undef;
  field $type          : reader = undef;

  field $attribute_list = [];
  field $citation_list  = [];
  field $child_ref_list = [];
  field $event_ref_list = [];
  field $note_list      = [];
  field $tag_list       = [];

  ADJUST {
    $complete      = $data->{complete};
    $father_handle = $data->{father_handle};
    $gramps_id     = $data->{gramps_id};
    $handle        = $data->{handle};
    $mother_handle = $data->{mother_handle};
    $private       = $data->{private};
    $type = App::Schierer::HPFan::Model::Gramps::Family::Relationship->new(
      $data->{type}->%*);

    foreach my $item ($data->{attribute_list}->@*) {
      push @$attribute_list, $item;
    }

    foreach my $item ($data->{child_ref_list}->@*) {
      push @$child_ref_list,
        App::Schierer::HPFan::Model::Gramps::Person::Child::Reference->new(
        data => $item);
    }

    foreach my $item ($data->{citation_list}->@*) {
      push @$citation_list, $item;
    }

    foreach my $item ($data->{event_ref_list}->@*) {
      push @$event_ref_list,
        App::Schierer::HPFan::Model::Gramps::Event::Reference->new(
        data => $item);
    }

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }
  }

  method event_ref_list { [$event_ref_list->@*] }
  method child_ref_list { [$child_ref_list->@*] }
  method citation_list  { [$citation_list->@*] }
  method attribute_list { [$attribute_list->@*] }
  method note_list      { [$note_list->@*] }
  method tag_list       { [$tag_list->@*] }

  method has_parent($person_handle) {
    return 1 if $father_handle && $father_handle eq $person_handle;
    return 1 if $mother_handle && $mother_handle eq $person_handle;
    return 0;
  }

  method has_child($person_handle) {
    for my $child_ref_list (@$child_ref_list) {
      return 1 if $child_ref_list->ref eq $person_handle;
    }
    return 0;
  }

  method to_string() {
    my @parts;

    if ($father_handle || $mother_handle) {
      my $father = $father_handle || "Unknown";
      my $mother = $mother_handle || "Unknown";
      push @parts, "Parents: $father & $mother";
    }

    if (@$child_ref_list) {
      my $child_count = scalar @$child_ref_list;
      push @parts, "Children: $child_count";
    }

    my $desc = @parts ? join(", ", @parts) : "Empty family";
    return sprintf("Family[%s]: %s", $handle, $desc);
  }
}

1;
