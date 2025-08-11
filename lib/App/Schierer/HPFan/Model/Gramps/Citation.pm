use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Citation :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  require App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $handle     : reader : param = undef;
  field $id         : reader : param = undef;
  field $change     : reader : param = Date::Manip::Date->new();
  field $page       : reader : param = '';
  field $confidence : reader : param = 0;
  field $sourceref  : reader : param = undef;
  field $date       : param = undef;

  method date {
    my $df = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    return $df->format_date($date);
  }
}
1;
__END__
