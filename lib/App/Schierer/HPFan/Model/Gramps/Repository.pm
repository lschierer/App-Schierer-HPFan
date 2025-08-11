use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Repository :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $handle : param : reader = undef;
  field $change : param : reader = Date::Manip::Date->new();
  field $id     : param : reader = undef;
  field $rname  : param : reader = undef;
  field $type   : param : reader = undef;
  field $url    : param : reader = undef;

}
1;
__END__
