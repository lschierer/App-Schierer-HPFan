use 5.42.0;
use utf8::all;
use experimental qw(class);
use File::FindLib 'lib';
require File::Share;
use File::HomeDir;
require Path::Tiny;
require Log::Log4perl;
require Log::Log4perl::Config;

package App::Schierer::HPFan::Logger::Config {
  use Carp;
  use Log::Log4perl qw(:levels);

  our $config_file;
  our $logger;

  sub new ($class) {
    #say "Game::EvonyTKR::Logger::Config new sub";
    my $self = { };
    bless $self, $class;
  }

  sub get_config_file ($self, $mode = 'production') {
    my $dir = Path::Tiny::path(File::Share::dist_dir('App::Schierer::HPFan'));
    $config_file = $dir->child("log4perl.${mode}.conf");
    if(! -f -r $config_file){
      Log::Log4perl->easy_init($ERROR);
      my $logger = Log::Log4perl->get_logger('App::Schierer::HPFan');
      $logger->logcroak("$config_file does not exist or is not readable.");
    }
    return $config_file;
  }

  sub getLogDir {
    my $home = File::HomeDir->my_home;
    my $logDir =
      Path::Tiny::path($home)->child('var/log/Perl/dist/App-Schierer-HPFan/');
    return $logDir;
  }

  sub init ($self, $mode = 'production') {
    my $cf;
    unless(defined $config_file) {
      $cf = $self->get_config_file($mode);
    } else {
      $cf = $config_file;
    }

    # set up the target directory
    my $target = $self->getLogDir();
    $target->mkdir({mode => 0755 });

    Log::Log4perl::Config->utf8(1);
    if($mode =~ /production/i) {
      Log::Log4perl::init_and_watch($config_file->absolute->canonpath,10);
    } else {
      Log::Log4perl::init($config_file->absolute->canonpath);
    }
    $logger = Log::Log4perl->get_logger('App::Schierer::HPFan');
    $logger->info("logging initialized using $cf for mode $mode");
    return $logger;
  }

  sub get_logger ($self) {
    unless(defined $logger) {
      $self->init();
    }
    return $logger;
  }

}
1;
__END__
