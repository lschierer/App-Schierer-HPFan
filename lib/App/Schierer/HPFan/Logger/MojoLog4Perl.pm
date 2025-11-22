use v5.42.0;
use utf8::all;

# lib/App/HPFan/MojoLog4perl.pm
package App::Schierer::HPFan::Logger::MojoLog4Perl;
use Mojo::Base 'Mojo::Log', -role, -signatures;
use Log::Log4perl;
use Log::Log4perl::Level;
require File::HomeDir::Tiny;
require Data::Printer;
use Carp;

sub logFileLocation {
  my $mode = $ENV{'MOJO_MODE'} // 'production';
  say "mode is $mode";
  my $userHome = File::HomeDir::Tiny::home();
  my @parts    = split '::', __PACKAGE__;
  my $base     = join '-', @parts[0 .. 2];
  my $logDir =
    Mojo::File->new(sprintf('%s/var/log/Perl/dist/%s', $userHome, $base));
  # Create directory if needed
  $logDir->make_path({ mode => 0711 })
    unless -d $logDir->to_abs->to_string;
  return $logDir;
}

sub appender_setup {
  my $logDir = __PACKAGE__->logFileLocation();
  my $config = qq(
    log4perl.rootLogger = WARN, LOGFILE
    log4perl.appender.LOGFILE = Log::Log4perl::Appender::File
    log4perl.appender.LOGFILE.filename = $logDir/app-$$.log
    log4perl.appender.LOGFILE.mode = append
    log4perl.appender.LOGFILE.utf8 = 1
    log4perl.appender.LOGFILE.layout = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.LOGFILE.layout.ConversionPattern = [%p] %d (%C line %L) %m%n
  );
  return $config;
}

our $logLevels = {
  'App::LinkChecker::Command'                                         => 'WARN',
  'App::Schierer::HPFan'                                              => 'WARN',
  'App::Schierer::HPFan::Controller::AutoIndex'                       => 'WARN',
  'App::Schierer::HPFan::Controller::Bookmarks'                       => 'WARN',
  'App::Schierer::HPFan::Controller::ControllerBase'                  => 'WARN',
  'App::Schierer::HPFan::Controller::Families'                        => 'WARN',
  'App::Schierer::HPFan::Controller::History'                         => 'WARN',
  'App::Schierer::HPFan::Controller::HPNOFP'                          => 'WARN',
  'App::Schierer::HPFan::Controller::People'                          => 'WARN',
  'App::Schierer::HPFan::Data'                                        => 'WARN',
  'App::Schierer::HPFan::Logger'                                      => 'WARN',
  'App::Schierer::HPFan::Logger::Config'                              => 'WARN',
  'App::Schierer::HPFan::Logger::MojoLog4Perl'                        => 'WARN',
  'App::Schierer::HPFan::Model::CustomDate'                           => 'WARN',
  'App::Schierer::HPFan::Model::Gedcom'                               => 'WARN',
  'App::Schierer::HPFan::Model::Gramps'                               => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Attribute'                    => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Citation'                     => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Event'                        => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Event::Reference'             => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type' => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Event::Type'                  => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Family'                       => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Family::Relationship'         => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Generic'                      => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Name'                         => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Note'                         => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Note::Text'                   => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Note::Type'                   => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Person'                       => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Person::Child::Reference'     => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type' =>
    'WARN',
  'App::Schierer::HPFan::Model::Gramps::Reference'             => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Repository'            => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Repository::MediaType' => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Repository::Reference' => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Repository::Type'      => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Source'                => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Surname'               => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Tag'                   => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Url'                   => 'WARN',
  'App::Schierer::HPFan::Model::Gramps::Utilities'             => 'WARN',
  'App::Schierer::HPFan::Model::History::Event'                => 'WARN',
  'App::Schierer::HPFan::Model::History::Gramps'               => 'WARN',
  'App::Schierer::HPFan::Model::History::Gramps::footnote'     => 'WARN',
  'App::Schierer::HPFan::Model::History::YAML'                 => 'WARN',
  'App::Schierer::HPFan::Plugins::ClassLists'                  => 'WARN',
  'App::Schierer::HPFan::Plugins::Markdown'                    => 'WARN',
  'App::Schierer::HPFan::Plugins::Navigation'                  => 'WARN',
  'App::Schierer::HPFan::Plugins::StaticPages'                 => 'WARN',
  'App::Schierer::HPFan::View::Markdown'                       => 'WARN',
  'App::Schierer::HPFan::View::Timeline'                       => 'WARN',
  'App::Schierer::HPFan::View::Timeline::PositionHelpers'      => 'WARN',
  'App::Schierer::HPFan::View::Timeline::Utilities'            => 'WARN',
  'Test::Package'                                              => 'DEBUG',
};

sub logger ($class, $caller = undef) {
  state $I_Have_Init;
  $caller //= 'undef::package';

  my $mode = $ENV{'MOJO_MODE'} // 'production';
  my $default = $mode eq 'development' ? 'DEBUG' : 'WARN';

  # MUST initialize Log4perl BEFORE any logging calls
  unless (Log::Log4perl->initialized()) {
    $I_Have_Init = 1;
    my $config = __PACKAGE__->appender_setup();
    foreach my $package (keys %$logLevels) {
      my $level = $logLevels->{$package};
      $config .= "log4perl.logger.$package = $level\n";
    }
    Log::Log4perl->init(\$config);
  }
  elsif (!$I_Have_Init) {
    $I_Have_Init = 1;
    # Force re-initialization to override any auto-config from another source
    foreach my $package (keys %$logLevels) {
      my $level = $logLevels->{$package};
      my $ll    = Log::Log4perl->get_logger($package);
      $ll->level(Log::Log4perl::Level::to_priority($level));
    }
  }

  # NOW safe to get loggers and log - Log4perl is initialized
  my $l4p = Log::Log4perl->get_logger($class);
  my $ll = exists $logLevels->{$class} ? Log::Log4perl::Level::to_priority($logLevels->{$class}) : $default;
  $l4p->level($ll);
  $l4p->debug(
    sprintf('in %s, $class is %s, $caller is %s', __PACKAGE__, $class, $caller)
  );

  my $cl = Log::Log4perl->get_logger($caller);
  $l4p->debug(sprintf(
    'returning logger in %s, $class is %s, for %s at level %s',
    __PACKAGE__, $class,
    $caller, Log::Log4perl::Level::to_level($cl->level()),
  ));
  return $cl;
}

sub debug { shift->_fwd(debug => @_) }
sub info  { shift->_fwd(info  => @_) }
sub warn  { shift->_fwd(warn  => @_) }
sub error { shift->_fwd(error => @_) }
sub fatal { shift->_fwd(fatal => @_) }

# (optional) Mojolicious also calls ->trace in some versions
sub trace { shift->_fwd(trace => @_) }    # map to debug if you want

sub _fwd {
  my ($self, $level, @lines) = @_;
  my $msg = join('', map { ref($_) ? "$_" : $_ } @lines);
  $self->logger->$level($msg);
  return $self;
}

1;
__END__
