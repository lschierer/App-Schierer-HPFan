use v5.42.0;
use experimental qw(class);
use utf8::all;
use namespace::autoclean;

class App::Schierer::HPFan::Logger {
  use Carp;
  use Log::Log4perl qw(:levels);    # <-- do NOT import get_logger
  use Scalar::Util  qw(blessed);
  use JSON::PP      ();
  use Env           qw(DEV_MODE PERL_ENV MOJO_MODE);

  our $VERSION = 'v0.0.3';
  use overload
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 0;                        # allow Perl defaults for the rest

  field $logger : reader;                   # readonly accessor -> $obj->logger
  field $category : reader : param = __CLASS__;

  field $_debug : reader = 0;

  ADJUST {
    # decide dev-ness; prefer DEV_MODE, else PERL_ENV/MOJO_MODE
    my $v = $DEV_MODE // $PERL_ENV // $MOJO_MODE // '';
    $_debug = ($v && $v !~ /^(?:0|false|prod(?:uction)?)$/i) ? 1 : 0;

    $self->get_logger
      ;   # initialize on construction (merged from a pre-existing ADJUST block)
  }

  # Normalize $level to a Log::Log4perl constant if a string is given
  method _norm_level ($level) {
    return $level if defined $level && $level =~ /^\d+$/;   # already a constant
    my %by_name = (
      trace => $TRACE,
      debug => $DEBUG,
      info  => $INFO,
      warn  => $WARN,
      error => $ERROR,
      fatal => $FATAL,
    );
    return $by_name{ lc($level // '') } // $WARN;
  }

  method dev_guard ($msg, $level = $WARN) {
    if ($self->_debug) { $self->logger->logcroak($msg) }
    else               { $self->logger->log($self->_norm_level($level), $msg) }
    return;
  }

  method get_logger {
    return $logger if defined $logger;
    # If you use a Log4perl config, make sure it's already initialized elsewhere
    Log::Log4perl::Config->utf8(1)
      ;    # only if you really need this, and you've loaded that module
    $logger = Log::Log4perl->get_logger($category); # <-- set the field directly
    return $logger;
  }

  # ----- Log::Handler-compatible shim (what Genealogy::Gedcom expects) -----

  method log ($message, $level = 'info') {
    $self->_log4perl_forwarder($message, $level);
  }
  method debug   ($message) { $self->_log4perl_forwarder($message, $DEBUG) }
  method info    ($message) { $self->_log4perl_forwarder($message, $INFO) }
  method notice  ($message) { $self->_log4perl_forwarder($message, $INFO) }
  method warning ($message) { $self->_log4perl_forwarder($message, $WARN) }
  method error   ($message) { $self->_log4perl_forwarder($message, $ERROR) }
  method critical($message) { $self->_log4perl_forwarder($message, $FATAL) }
  method alert ($message)   { $self->_log4perl_forwarder($message, $WARN) }

  method emergency($message) {
    $self->_log4perl_forwarder($message, 'emergency');
  }

  method _log4perl_forwarder ($message, $level) {
    my $lvl = $INFO;    # default
    if    ($level eq 'debug')                       { $lvl = $DEBUG }
    elsif ($level eq 'info' or $level eq 'notice')  { $lvl = $INFO }
    elsif ($level eq 'warning' or $level eq 'warn') { $lvl = $WARN }
    elsif ($level eq 'error' or $level eq 'err')    { $lvl = $ERROR }
    elsif ($level eq 'critical'
      or $level eq 'crit'
      or $level eq 'alert'
      or $level eq 'emergency') {
      $lvl = $FATAL;
    }

    $self->get_logger->log($lvl, $message);
  }

  # ----- Optional helpers for DDP / JSON -----

  method to_hash {
    return { category => $category };
  }

  method TO_JSON {
    return $self->to_hash;
  }

  method to_string {
    return JSON::PP->new->utf8->allow_blessed->convert_blessed->encode($self);
  }

  method _isTrue {
    return
         defined($self)
      && ref($self)
      && blessed($self)
      && blessed($self) eq __CLASS__;
  }
}
1;
