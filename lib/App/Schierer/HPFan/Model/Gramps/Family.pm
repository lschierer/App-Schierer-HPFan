use v5.42;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference;
require App::Schierer::HPFan::Model::Gramps::Person::Reference;
require App::Schierer::HPFan::Model::Gramps::Family::Relationship;

class App::Schierer::HPFan::Model::Gramps::Family :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;

  field $gramps_id     = undef;
  field $father_handle = undef;    # handle reference
  field $mother_handle = undef;    # handle reference

  field $rel_type   = undef;       # relationship type
  field $attributes = [];
  field $child_refs = [];
  field $event_refs = [];

  ADJUST {
    my @desired = qw( gramps_id change private gramps_id
      father_handle
      mother_handle
      json_data     );
    my @names;
    push @names, @desired;
    push @names, keys $self->ALLOWED_FIELD_NAMES->%*;
    foreach my $tn (@names) {
      if (any { $_ eq $tn } @desired) {
        $self->ALLOWED_FIELD_NAMES->{$tn} = 1;
      }
      else {
        $self->ALLOWED_FIELD_NAMES->{$tn} = undef;
      }
    }
  }

  method event_refs() { [@$event_refs] }
  method child_refs() { [@$child_refs] }
  method attributes() { [@$attributes] }

  method gramps_id     { $self->_get_field('gramps_id') }
  method father_handle { $self->_get_field('father_handle') }
  method mother_handle { $self->_get_field('mother_handle') }
  method private       { $self->_get_field('private') }
  method json_data     { $self->_get_field('json_data') }

  method rel_type {
    my $hash = JSON::PP->new->decode($self->json_data);
    return App::Schierer::HPFan::Model::Gramps::Family::Relationship->new(
      $hash->{'type'}->%*);
  }

  method has_parent($person_handle) {
    return 1 if $father_handle && $father_handle eq $person_handle;
    return 1 if $mother_handle && $mother_handle eq $person_handle;
    return 0;
  }

  method has_child($person_handle) {
    for my $child_ref (@$child_refs) {
      return 1 if $child_ref->ref eq $person_handle;
    }
    return 0;
  }

  method parse_json_data {
    #trust DBH::SQLite to have already handle UTF8.
    my $hash = JSON::PP->new->decode($self->json_data);
    if (reftype($hash) eq 'HASH') {
      $self->logger->info("got hash " . Data::Printer::np($hash));

      foreach my $item ($hash->{'event_ref_list'}->@*) {
        push @$event_refs,
          App::Schierer::HPFan::Model::Gramps::Event::Reference->new($item->%*);
      }

      foreach my $item ($hash->{'child_ref_list'}->@*) {
        push @$child_refs,
          App::Schierer::HPFan::Model::Gramps::Person::Reference->new(
          $item->%*);
      }

    }
  }

  method to_string() {
    my @parts;

    if ($father_handle || $mother_handle) {
      my $father = $father_handle || "Unknown";
      my $mother = $mother_handle || "Unknown";
      push @parts, "Parents: $father & $mother";
    }

    if (@$child_refs) {
      my $child_count = scalar @$child_refs;
      push @parts, "Children: $child_count";
    }

    my $desc = @parts ? join(", ", @parts) : "Empty family";
    return sprintf("Family[%s]: %s", $self->handle, $desc);
  }
}

1;
