use v5.42.0;
use utf8::all;
use experimental qw(class);
use File::FindLib 'lib';
require Mojo::File::Share;
require Mojo::Home;
require App::Schierer::HPFan::Controller::ControllerBase;
require App::Schierer::HPFan::Service::LogAdapter;

package App::Schierer::HPFan {
  use Mojo::Base 'Mojolicious',                       -strict, -signatures;
  use Mojo::Base 'App::Schierer::HPFan::Role::Logging', -role,   -signatures;
  use Mojo::Loader qw(find_modules load_class);
  use Log::Any::Adapter;
  use Log::Log4perl;
  use Carp;
  use Env qw(DEPLOYMENT_TIME HOSTNAME IMAGE_TAG IMAGE_URI);
  our $VERSION = 'v0.00.1';
  use diagnostics;

  BEGIN {
    App::Schierer::HPFan::Role::Logging::get_logger(__PACKAGE__);
  }

# This method will run once at server start
  sub startup ($app) {
    # Set up Log::Any adapter BEFORE accessing $app->log
    Log::Any::Adapter->set('Log4perl');
    $app->plugin('Log::Any' => { logger => 'Log::Log4perl' });
    $app->log_debug('setting up logging');
    $app->log->info(sprintf('Mojolicious Logging initialized'));

    ## Load configuration from config file
    my $config  = $app->plugin('NotYAMLConfig');
    my $distDir = Mojo::File::Share::dist_dir('App::Schierer::HPFan');
    my $mode    = $app->mode;
    $app->config(distDir => $distDir);

    $app->config(APP_START_TIME => time());
    Env::import();
    $app->config(
      'HPFAN-Environment' => {
        DEPLOYMENT_TIME => $DEPLOYMENT_TIME,
        HOSTNAME        => $HOSTNAME,
        IMAGE_TAG       => $IMAGE_TAG,
        IMAGE_URI       => $IMAGE_URI,
      }
    );

    ## Configure the application
    $app->secrets($config->{secrets});
    $app->plugin('DefaultHelpers');
    $app->defaults(layout => 'default');

    foreach my $envkey (keys %{ $app->config->{'HPFAN-Environment'} }) {
      if (defined $envkey) {
        my $envValue = $app->config->{'HPFAN-Environment'}->{$envkey}
          // 'Undefined';
        $app->log_info("HPFAN-Environnment variable $envkey is $envValue");
      }
      else {
        $app->log_warn('undefined envkey in HPFAN-Environment!');
      }
    }

    ## Set namespaces
    push @{ $app->routes->namespaces },  'App::Schierer::HPFan::Controller';
    push @{ $app->plugins->namespaces }, 'App::Schierer::HPFan::Plugins';
    push @{ $app->plugins->namespaces }, 'App::Schierer::HPFan::Controller';
    push @{ $app->preload_namespaces },  'App::Schierer::HPFan::Controller';

    # Register infrastructure plugins in specific order

    # First Plugins that provide helpers but do not define routes
    # Helper for the class list tables
    $app->plugin('App::Schierer::HPFan::Plugins::ClassLists');

    my @controllerplugins = find_modules 'App::Schierer::HPFan::Controller';
    $app->log_info(
      sprintf('found %s controller plugins', scalar(@controllerplugins)));
    foreach my $module (sort @controllerplugins) {
      if (my $e = load_class($module)) {
        my $errmessage = sprintf('loading module "%s" failed: %s', $module, $e);
        print STDERR $errmessage;
        $app->log_error($errmessage);
        croak($errmessage);
      }
      else {
        next if ($module eq 'App::Schierer::HPFan::Controller::ControllerBase');
        eval {
          $app->plugin($module);
          $app->log->debug("loaded $module");
        } or do {
          $app->log_error(sprintf('failed to load module %s: %s', $module, $@));
        }
      }
    }


    # Register last for lowest priority

    if ($mode eq 'development') {
      $app->app->hook(
        before_render => sub ($c, $args) {
          $app->log_info(
            sprintf
            'before_render %s -> template=%s layout=%s '.'handler=%s inline?=%s text?=%s',
            $c->req->url->path->to_string,
            ($args->{template} // ''),
            ($args->{layout}   // ''),
            ($args->{handler}  // '[auto]'),
            (exists $args->{inline} ? 'yes' : 'no'),
            (exists $args->{text}   ? 'yes' : 'no'),
          );
        }
      );

      $app->app->hook(
        after_render => sub ($c, $output, $format) {
          $app->log_info(
            sprintf 'after_render %s bytes=%d format=%s',
            $c->req->url->path->to_string,
            length($$output // ''),
            ($format // '[undef]')
          );
        }
      );
    }
    else {
      $app->log_info("Running in mode $mode");
    }

  }

}

1;
__END__
