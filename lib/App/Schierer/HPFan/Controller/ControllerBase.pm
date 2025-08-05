use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
use namespace::clean;

package App::Schierer::HPFan::Controller::ControllerBase {
  use Mojo::Base 'Mojolicious::Controller';
  use Mojo::Base 'Mojolicious::Plugin', -role, -signatures;
  use Log::Log4perl;
  require Mojo::File;
  require YAML::PP;
  require Data::Printer;
  use Carp;

  sub getBase ($self) {
    return "/" . __PACKAGE__;
  }

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info("ControllerBase register function");

    $app->helper(logger => sub { return $logger });

    my $routes = $app->routes;

    $routes->get('/favicon.svg')->to(
      cb => sub ($c) {
        $c->reply->static('images/favicon.svg');
      }
    );

    $routes->get('/health')->to(
      cb => sub($c) {
        $c->render(
          json => {
            status  => 'ok',
            mode    => $app->mode // 'unknown',
            version => $app->VERSION,
            time    => scalar localtime,
          },
          status => 200
        );
      }
    );

  }

}
1;

__END__
