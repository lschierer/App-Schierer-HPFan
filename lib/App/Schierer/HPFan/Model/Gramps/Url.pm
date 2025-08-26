use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require URI;

class App::Schierer::HPFan::Model::Gramps::Url :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '<=>' => \&_comparison,
    '=='  => \&_equality,
    '!='  => \&_inequality,
    '""'  => \&as_string;

  field $_class       : param //= undef;
  field $desc         : reader : param //= undef;
  field $path         : reader : param //= undef;
  field $private      : reader : param //= 0;
  field $type         : reader : param //= undef;

  method href {
    return URI->new($path);
  }

  ADJUST {
    if (not defined($path)) {
      $self->logger->logcroak(
        'path must be provided.');
    }
  }

  method as_string {
    if ($private) {
      return '';
    }
    if (not(defined($type) and defined($desc))) {
      return "<$self->href>";
    }
    else {
      my @parts;
      push @parts, $type;
      push @parts, "<$self->href>";
      push @parts, $desc;
      return join '; ', @parts;
    }
  }
}
1;
