use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Name {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::Surname;

  field $alt        : reader : param = 0;
  field $type       : reader : param = "Birth Name";
  field $priv       : reader : param = 0;
  field $sort       : reader : param = undef;
  field $display    : reader : param = undef;
  field $first      : reader : param = undef;
  field $call       : reader : param = undef;
  field $surnames   : param = [];
  field $suffix     : reader : param = undef;
  field $title      : reader : param = undef;
  field $nick       : reader : param = undef;
  field $familynick : reader : param = undef;
  field $group      : reader : param = undef;
  field $date       : reader : param =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $note_refs     : param = [];
  field $citation_refs : param = [];

  ADJUST {
    # Validate that surnames is an array of Surname objects
    if (@$surnames) {
      for my $surname (@$surnames) {
        croak "surnames must be Surname objects"
          unless ref($surname) eq
          'App::Schierer::HPFan::Model::Gramps::Surname';
      }
    }
  }

  method surnames() { [@$surnames] }

  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }

  method primary_surname() {
    # Return the primary surname (prim=1) or first surname
    for my $surname (@$surnames) {
      return $surname if $surname->prim;
    }
    return @$surnames ? $surnames->[0] : undef;
  }

  method to_string() {
    my @parts;

    push @parts, $title if $title;
    push @parts, $first if $first;

    if (my $primary_surname = $self->primary_surname) {
      push @parts, $primary_surname->to_string;
    }

    push @parts, $suffix if $suffix;

    my $name = join(" ", @parts) || "Unknown";

    if ($nick) {
      $name .= " \"$nick\"";
    }

    return $name;
  }
}

1;
