use v5.42.0;
use experimental qw(class);
use utf8::all;

class App::Schierer::HPFan::Model::Base;
use Carp;
require App::Schierer::HPFan::Role::Logging;

method logger {
  state $l4p //= App::Schierer::HPFan::Role::Logging::get_logger(__CLASS__);
  return $l4p;
}

1;
__END__
