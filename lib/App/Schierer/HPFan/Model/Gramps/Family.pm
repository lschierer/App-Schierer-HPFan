use v5.42;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Family {
  use Carp;

  field $id             :reader : param = undef;
  field $handle         :reader : param;
  field $priv           :reader : param = 0;
  field $change         :reader : param;
  field $rel_type       :reader : param = undef;  # relationship type
  field $father_ref     :reader : param = undef;  # handle reference
  field $mother_ref     :reader : param = undef;  # handle reference
  field $event_refs     : param = [];
  field $child_refs     : param = [];     # array of hashrefs with hlink, mrel, frel
  field $attributes     : param = [];
  field $note_refs      : param = [];
  field $citation_refs  : param = [];
  field $tag_refs       : param = [];

  ADJUST {
    croak "handle is required"           unless defined $handle;
    croak "change timestamp is required" unless defined $change;

    # Validate child_refs structure
    if (@$child_refs) {
      for my $child_ref (@$child_refs) {
        croak "child_refs must be hashrefs with hlink"
          unless ref($child_ref) eq 'HASH' && exists $child_ref->{hlink};
      }
    }
  }


  method event_refs()    { [@$event_refs] }
  method child_refs()    { [@$child_refs] }
  method attributes()    { [@$attributes] }
  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }
  method tag_refs()      { [@$tag_refs] }

  method has_parent($person_handle) {
    return 1 if $father_ref && $father_ref eq $person_handle;
    return 1 if $mother_ref && $mother_ref eq $person_handle;
    return 0;
  }

  method has_child($person_handle) {
    for my $child_ref (@$child_refs) {
      return 1 if $child_ref->{hlink} eq $person_handle;
    }
    return 0;
  }

  method to_string() {
    my @parts;

    if ($father_ref || $mother_ref) {
      my $father = $father_ref || "Unknown";
      my $mother = $mother_ref || "Unknown";
      push @parts, "Parents: $father & $mother";
    }

    if (@$child_refs) {
      my $child_count = scalar @$child_refs;
      push @parts, "Children: $child_count";
    }

    my $desc = @parts ? join(", ", @parts) : "Empty family";
    return sprintf("Family[%s]: %s", $handle, $desc);
  }
}

1;
