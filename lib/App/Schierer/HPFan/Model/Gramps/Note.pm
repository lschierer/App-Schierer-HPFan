use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Note :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $handle : reader : param = undef;
  field $id     : reader : param = undef;
  field $change : reader : param = Date::Manip::Date->new();
  field $type   : reader : param = '';
  field $text   : reader : param = '';

}
1;
__END__
