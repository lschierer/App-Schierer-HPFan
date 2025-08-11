use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Source :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  require App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $handle    : reader : param = undef;
  field $change    : reader : param = Date::Manip::Date->new();
  field $id        : reader : param = undef;
  field $stitle    : reader : param = undef;
  field $sauthor   : reader : param = undef;
  field $spubinfo  : reader : param = undef;
  field $repo_refs : param = [];

  method repo_refs() { [@$repo_refs] }
}
1;
__END__
