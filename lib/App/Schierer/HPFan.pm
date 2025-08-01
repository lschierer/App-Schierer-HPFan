use 5.42.0;
use utf8::all;
use experimental qw(class);
use File::FindLib 'lib';
require Mojo::File::Share;
require Mojo::Home;
require App::Schierer::HPFan::Logger::Config;

package App::Schierer::HPFan {
  use Mojo::Base 'Mojolicious', -signatures;
  use Carp;
  our $VERSION = 'v0.00.1';

# This method will run once at server start
  sub startup ($self) {

    # Load configuration from config file
    my $config = $self->plugin('NotYAMLConfig');
    my $distDir = Mojo::File::Share::dist_dir('App::Schierer::HPFan');
    my $mode         = $self->mode;

    # Configure the application
    $self->secrets($config->{secrets});

    my $lc = App::Schierer::HPFan::Logger::Config->new();
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

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/')->to('Example#welcome');
  }

}

1;
__END__
