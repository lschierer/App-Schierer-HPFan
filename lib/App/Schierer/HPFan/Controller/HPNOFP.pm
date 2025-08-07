use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::People {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';
  use Log::Log4perl;
  require Data::Printer;
  use Carp;

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info("::Controller::People register function");
  }
}
1;
__END__
