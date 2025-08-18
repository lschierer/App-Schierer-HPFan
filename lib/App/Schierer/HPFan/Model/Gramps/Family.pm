use v5.42;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference;
require App::Schierer::HPFan::Model::Gramps::Person::Reference;
require App::Schierer::HPFan::Model::Gramps::Family::Relationship;

class App::Schierer::HPFan::Model::Gramps::Family :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $gramps_id     : param = undef;
  field $father_handle : param = undef;    # handle reference
  field $mother_handle : param = undef;    # handle reference
  field $json_data     : param //= undef;

  field $rel_type   : param = undef;  # relationship type
  field $event_refs : param = [];
  field $child_refs : param = [];     # array of hashrefs with hlink, mrel, frel
  field $attributes : param = [];
  field $note_refs  : param = [];
  field $citation_refs : param = [];
  field $tag_refs      : param = [];
  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw( gramps_id change private json_data) };

  method event_refs()    { [@$event_refs] }
  method child_refs()    { [@$child_refs] }
  method attributes()    { [@$attributes] }
  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }
  method tag_refs()      { [@$tag_refs] }

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

      foreach my $item ($hash->{'citation_list'}->@*) {
        push @$citation_refs, $item,;
      }

      foreach my $item ($hash->{'note_list'}->@*) {
        push @$note_refs, $item,;
      }

      foreach my $item ($hash->{'tag_list'}->@*) {
        push @$tag_refs, $item,;
      }

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
