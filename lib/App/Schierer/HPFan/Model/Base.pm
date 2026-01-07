use v5.42.0;
use experimental qw(class);
use utf8::all;

class App::Schierer::HPFan::Model::Base;
use Carp;
require Log::Handler;

method logger {
  state $l //= Log::Handler->create_logger(__CLASS__);
  return $l;
}

method _isTrue {
  return 1;
}

method dev_guard ($message) {
  $self->logger->warn("DEV_GUARD: $message");
}

1;
__END__
