use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Tag {
  use Carp;

  field $handle   : reader : param;
  field $name     : reader : param;
  field $color    : reader : param;
  field $priority : reader : param;
  field $change   : reader : param;

  ADJUST {
    croak "handle is required"           unless defined $handle;
    croak "name is required"             unless defined $name;
    croak "color is required"            unless defined $color;
    croak "priority is required"         unless defined $priority;
    croak "change timestamp is required" unless defined $change;

    # Validate color format (should be hex color)
    if ($color && $color !~ /^#[0-9A-Fa-f]{6}$/) {
      croak "color must be in hex format (#RRGGBB): $color";
    }

    # Validate priority is numeric
    if ($priority && $priority !~ /^\d+$/) {
      croak "priority must be numeric: $priority";
    }
  }

  method to_string() {
    return sprintf("Tag[%s]: %s (priority: %s, color: %s)",
      $handle, $name, $priority, $color);
  }
}

1;
