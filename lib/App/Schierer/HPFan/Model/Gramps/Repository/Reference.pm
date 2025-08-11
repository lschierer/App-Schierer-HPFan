use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Repository::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $handle : param : reader = undef;
  field $medium : param : reader = undef;

}
1;
__END__
