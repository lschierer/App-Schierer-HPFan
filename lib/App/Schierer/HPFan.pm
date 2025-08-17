use v5.42.0;
use utf8::all;
use experimental qw(class);
use File::FindLib 'lib';
require Mojo::File::Share;
require Mojo::Home;
require App::Schierer::HPFan::Logger::Config;
require App::Schierer::HPFan::Controller::ControllerBase;

package App::Schierer::HPFan {
  use Mojo::Base 'Mojolicious', -strict, -signatures;
  use Carp;
  use Env qw(DEPLOYMENT_TIME HOSTNAME IMAGE_TAG IMAGE_URI);
  our $VERSION = 'v0.00.1';

# This method will run once at server start
  sub startup ($self) {

    # Load configuration from config file
    my $config  = $self->plugin('NotYAMLConfig');
    my $distDir = Mojo::File::Share::dist_dir('App::Schierer::HPFan');
    my $mode    = $self->mode;
    $self->config(distDir        => $distDir);
    $self->config(APP_START_TIME => time());
    Env::import();
    $self->config(
      'HPFAN-Environment' => {
        DEPLOYMENT_TIME => $DEPLOYMENT_TIME,
        HOSTNAME        => $HOSTNAME,
        IMAGE_TAG       => $IMAGE_TAG,
        IMAGE_URI       => $IMAGE_URI,
      }
    );

    # Configure the application
    $self->secrets($config->{secrets});
    $self->plugin('DefaultHelpers');

    my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
    my $log4perl_logger = $lc->init($mode);
    $self->log->handle(undef);    # Disable default Mojo logger
    $self->log->level('debug');
    $self->log->on(
      message => sub ($log, $level, @lines) {
        my $msg = join "\n", @lines;
        $log4perl_logger->$level($msg) if $log4perl_logger->can($level);
      }
    );
    $self->log->info("Mojolicious Logging initialized");
    foreach my $envkey (keys %{ $self->config->{'HPFAN-Environment'} }) {
      if (defined $envkey) {
        my $envValue = $self->config->{'HPFAN-Environment'}->{$envkey}
          // 'Undefined';
        $self->log->info("HPFAN-Environnment variable $envkey is $envValue");
      }
      else {
        $self->log->warn('undefined envkey in HPFAN-Environment!');
      }
    }

    # Set namespaces
    push @{ $self->routes->namespaces },  'App::Schierer::HPFan::Controller';
    push @{ $self->plugins->namespaces }, 'App::Schierer::HPFan::Plugins';
    push @{ $self->plugins->namespaces }, 'App::Schierer::HPFan::Controller';
    push @{ $self->preload_namespaces },  'App::Schierer::HPFan::Controller';

    # Register infrastructure plugins in specific order

    # First Plugins that provide helpers but do not define routes
    # Markdown
    $self->plugin('App::Schierer::HPFan::Plugins::Markdown');
    # Helper for the class list tables
    $self->plugin('App::Schierer::HPFan::Plugins::ClassLists');
    # Navigation
    $self->plugin('App::Schierer::HPFan::Plugins::Navigation');

    # Then Controller Plugins
    $self->plugin(
      'Module::Loader' => {
        plugin_namespaces => ['App::Schierer::HPFan::Controller']
      }
    );

    # Last the Static Pages
    $self->plugin('App::Schierer::HPFan::Plugins::StaticPages');
    # Register last for lowest priority

    if ($mode eq 'development') {
      $self->app->hook(
        before_render => sub ($c, $args) {
          $c->log->info(
            sprintf
'before_render %s -> template=%s layout=%s handler=%s inline?=%s text?=%s',
            $c->req->url->path->to_string,
            ($args->{template} // ''),
            ($args->{layout}   // ''),
            ($args->{handler}  // '[auto]'),
            (exists $args->{inline} ? 'yes' : 'no'),
            (exists $args->{text}   ? 'yes' : 'no'),
          );
        }
      );

      $self->app->hook(
        after_render => sub ($c, $output, $format) {
          $c->log->info(
            sprintf 'after_render %s bytes=%d format=%s',
            $c->req->url->path->to_string,
            length($$output // ''),
            ($format // '[undef]')
          );
        }
      );
    }
    else {
      $self->log->info("Running in mode $mode");
    }

  }

}

1;
__END__
