package App::Schierer::HPFan::Role::Logging;
use v5.42.0;
use experimental qw(class);
use utf8::all;
use Mojo::Base -role, -signatures;
use Log::Log4perl;
use Log::Log4perl::Level;
use Mojo::Loader        qw(find_modules);
use File::HomeDir::Tiny ();
require Data::Printer;
use List::AllUtils qw( uniq );
use Scalar::Util   qw(blessed);
use Carp;

my $logLevelOverrides;

BEGIN {
  our $DEBUG_LOGGING = $ENV{LOG_DEBUG} // 0;
}

has logger => sub ($package) {
  return get_logger($package);
};

##############################################################################
# Logging wrapper methods that use caller() to get the actual logging package
# This allows both roles and classes to have their own log level control
##############################################################################

sub log_trace ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->trace(@msg);
}

sub log_debug ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->debug(@msg);
}

sub log_info ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->info(@msg);
}

sub log_warn ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->warn(@msg);
}

sub log_error ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->error(@msg);
}

sub log_fatal ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->fatal(@msg);
}

sub log_logcroak ($self, @msg) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  $logger->logcroak(@msg);
}

# Check if log levels are enabled
sub is_trace ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_trace();
}

sub is_debug ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_debug();
}

sub is_info ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_info();
}

sub is_warn ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_warn();
}

sub is_error ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_error();
}

sub is_fatal ($self) {
  my $caller_package = caller(0);
  my $logger         = get_logger($caller_package);
  return $logger->is_fatal();
}

sub get_logger ($package) {
  my $pn = ref($package) ? blessed($package) : $package;

  # Strip __WITH__ role composition from package name
  $pn =~ s/__WITH__.+$//;

  my $l4p = Log::Log4perl->get_logger($pn);
  if (exists $logLevelOverrides->{$pn}) {
    unless (Log::Log4perl::Level::to_level($l4p->level()) eq
      $logLevelOverrides->{$pn}) {
      $l4p->level($logLevelOverrides->{$pn});
    }
  }
  if ($App::Schierer::HPFan::Role::Logging::DEBUG_LOGGING) {
    warn sprintf(
      'package "%s" is requesting a logger. Returning one with level %s',
      $pn, Log::Log4perl::Level::to_level($l4p->level()));
  }
  return $l4p;
}

sub debug_log_level ($caller) {
  return sprintf(
    'log level for %s is %s',
    ref($caller) ? ref($caller) : $caller,
    Log::Log4perl::Level::to_level($caller->logger->level())
  );
}

sub debug_log_category ($caller) {
  return sprintf(
    'log category for %s is %s',
    ref($caller) ? ref($caller) : $caller,
    $caller->logger->category()
  );
}

sub logFileLocation {
  my $mode = $ENV{'MOJO_MODE'} // 'production';
  warn "mode is $mode\n" if $App::Schierer::HPFan::Role::Logging::DEBUG_LOGGING;
  my $userHome = File::HomeDir::Tiny::home;
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
    log4perl.appender.LOGFILE.filename = $logDir/system.log
    log4perl.appender.LOGFILE.mode = append
    log4perl.appender.LOGFILE.utf8 = 1
    log4perl.appender.LOGFILE.layout = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.LOGFILE.layout.ConversionPattern = [%p] %d (%C line %L) %m%n
  );
  return $config;
}

BEGIN {
  my $mode        = $ENV{'MOJO_MODE'} // 'production';
  my $defaultMode = $mode eq 'development' ? 'DEBUG' : 'WARN';

  #(ALL|FATAL|TRACE|DEBUG|INFO|WARN|ERROR|FATAL|OFF)
  $logLevelOverrides = {
    'App::Schierer::HPFan'                             => 'DEBUG',
    'App::Schierer::HPFan::Controller::AutoIndex'      => 'INFO',
    'App::Schierer::HPFan::Controller::Bookmarks'      => 'WARN',
    'App::Schierer::HPFan::Controller::ControllerBase' => 'INFO',
    'App::Schierer::HPFan::Controller::Families'       => 'WARN',
    'App::Schierer::HPFan::Controller::History'        => 'DEBUG',
    'App::Schierer::HPFan::Controller::HPNOFP'         => 'WARN',
    'App::Schierer::HPFan::Controller::Harrypedia'     => 'DEBUG',
    'App::Schierer::HPFan::Controller::People'         => 'DEBUG',
    'App::Schierer::HPFan::Logger'                     => 'WARN',
    'App::Schierer::HPFan::Logger::Config'             => 'WARN',
    'App::Schierer::HPFan::Model::CustomDate'          => 'WARN',
    'App::Schierer::HPFan::Model::Gramps'              => 'WARN',
    'App::Schierer::HPFan::Model::Gramps::Citation'    => 'WARN',
    'App::Schierer::HPFan::Model::Gramps::Event'       => 'WARN',
    'App::Schierer::HPFan::Model::Gramps::Family'      => 'WARN',
    'App::Schierer::HPFan::Model::Gramps::Person'      => 'DEBUG',
    'App::Schierer::HPFan::Plugins::ClassLists'        => 'WARN',
    'App::Schierer::HPFan::Role::Gramps'               => 'DEBUG',
    'App::Schierer::HPFan::Role::Markdown'             => 'WARN',
    'App::Schierer::HPFan::Role::Navigation'           => 'WARN',
    'App::Schierer::HPFan::Role::StaticPages'          => 'WARN',
    'Test::Package'                                    => 'TRACE',
    'Test'                                             => 'TRACE',
  };

  if ($App::Schierer::HPFan::Role::Logging::DEBUG_LOGGING) {
    warn "Override keys: " . join(', ', keys %$logLevelOverrides) . "\n";
  }

  my $config = __PACKAGE__->appender_setup();

  my @packages = find_modules('App::Schierer::HPFan', { recursive => 1 });
  push @packages, keys %$logLevelOverrides;

  my @upn = sort { $a cmp $b } uniq @packages;

  foreach my $package (@upn) {
    $package = ref($package) ? blessed($package) : $package;
    # Convert :: to . for Log4perl category naming
    my $category = $package;
    $category =~ s/::/./g;
    if (exists $logLevelOverrides->{$package}) {
      my $level = $logLevelOverrides->{$package};
      $config .= "log4perl.logger.$category = ${level}\n";
    }
    else {
      my @parts       = split '::', $package;
      my $overrideSet = 0;
      while (scalar(@parts)) {
        pop(@parts);
        my $p = join('::', @parts);
        if (exists $logLevelOverrides->{$p}) {
          my $level = $logLevelOverrides->{$p};
          $config .= "log4perl.logger.$category = ${level}\n";
          $overrideSet = 1;
          last;
        }
      }
      $config .= "log4perl.logger.$category = ${defaultMode}\n"
        unless ($overrideSet);
    }
  }

  unless (Log::Log4perl->initialized()) {
    if ($App::Schierer::HPFan::Role::Logging::DEBUG_LOGGING) {
      warn "=== INITIALIZING LOG4PERL ===\n";
      warn "Mode: $mode, Default: $defaultMode\n";
      warn "Config:\n$config\n";
      warn "=== END CONFIG ===\n";
    }
    Log::Log4perl->init(\$config);
  }

  state $wrapperRegistered = 0;
  unless ($wrapperRegistered) {
    if ($App::Schierer::HPFan::Role::Logging::DEBUG_LOGGING) {
      warn sprintf('registering "%s" as a log4perl wrapper', __PACKAGE__)
        . "\n";
    }
    Log::Log4perl->wrapper_register(__PACKAGE__);
    $wrapperRegistered = 1;
  }
}

1;
__END__
