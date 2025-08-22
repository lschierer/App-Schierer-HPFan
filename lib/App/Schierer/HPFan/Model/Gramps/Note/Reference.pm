use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Note::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;



}
1;
__END__
field $ROLE_MAP;

ADJUST {
  # Shared built-in role map; 0 is “custom” (use $string)
  Readonly::Hash my %tmp => (
    1   => 'General',
    2   => 'Research',
    4   => 'Person Note',
    9   => 'Family Note',
    10  => 'Event Note',
    11  => 'Event Reference Note',
    19  => 'Child Reference Note',
    21  => 'Source Text',
    22  => 'Citation',
  );
  $ROLE_MAP = \%tmp;
}
