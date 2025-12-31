use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojo::File;
require YAML::PP;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::ControllerBase {
  use Mojo::Base 'Mojolicious::Controller';
  use Mojo::Base 'Mojolicious::Plugin',                        -role, -signatures;
  use Mojo::Base 'App::Schierer::HPFan::Role::Logging',        -role;
  use Mojo::Base 'App::Schierer::HPFan::Role::Markdown',       -role;
  use Mojo::Base 'App::Schierer::HPFan::Role::Navigation',     -role;
  use Mojo::Base 'App::Schierer::HPFan::Role::StaticPages',    -role;
  use Carp;

  sub getBase ($self) {
    return "/" . __PACKAGE__;
  }


  sub register($c, $app, $config //= {}) {
    $c->log_info(sprintf(
      'register function for %s.',
      __PACKAGE__
    ));

    my $routes = $app->routes;

    $routes->get('/favicon.svg')->to(
      cb => sub ($self) {
        $c->reply->static('images/favicon.svg');
      }
    );

    $routes->get('/health')->to(
      cb => sub($self) {
        my $APP_START_TIME = $app->config->{'APP_START_TIME'};
        $c->render(
          json => {
            status              => 'ok',
            mode                => $app->mode // 'unknown',
            time                => scalar localtime,
            app_started_at      => scalar(localtime($APP_START_TIME)),
            app_uptime_seconds  => time() - $APP_START_TIME,
            build_time          => $app->config->{'version'}->{'build-time'},
            cdk_deployment_time =>
              $app->config->{'HPFAN-Environment'}->{'DEPLOYMENT_TIME'}
              // 'unknown',
            container_id => $app->config->{'HPFAN-Environment'}->{'HOSTNAME'}
              // 'unknown',    # ECS sets this automatically
            image_tag => $app->config->{'HPFAN-Environment'}->{'IMAGE_TAG'}
              // 'unknown',
            image_uri => $app->config->{'HPFAN-Environment'}->{'IMAGE_URI'}
              // 'unknown',
            version    => $app->VERSION,
            git_commit => $app->config->{'version'}->{'git-commit'},
          },
          status => 200
        );
      }
    );

  }

}
1;

__END__
