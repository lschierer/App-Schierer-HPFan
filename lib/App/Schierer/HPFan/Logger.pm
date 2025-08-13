use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
use namespace::autoclean;

class App::Schierer::HPFan::Logger {
# PODNAME: App::Schierer::HPFan::Logger
  use Carp;
  use Log::Log4perl qw(get_logger :levels);
  our $VERSION = 'v0.0.2';

  field $logger : reader;

  field $category : reader : param = __CLASS__;

  ADJUST {
    $self->get_logger();
  }

  method get_logger {
    return $logger if defined $logger;
    Log::Log4perl::Config->utf8(1);
    $logger = Log::Log4perl->get_logger($category)
      ;    # $category is a field set to __CLASS__
    return $logger;
  }

  # Log::Handler methods to forward to Log::Log4perl
    # These methods are called by modules like Genealogy::Gedcom that expect
    # a Log::Handler instance.

    method log ($message, $level = 'info') {
      $self->_log4perl_forwarder($message, $level);
    }

    method debug ($message) {
      $self->_log4perl_forwarder($message, 'debug');
    }

    method info ($message) {
      $self->_log4perl_forwarder($message, 'info');
    }

    method notice ($message) {
      $self->_log4perl_forwarder($message, 'notice');
    }

    method warning ($message) {
      $self->_log4perl_forwarder($message, 'warning');
    }

    method error ($message) {
      $self->_log4perl_forwarder($message, 'error');
    }

    method critical ($message) {
      $self->_log4perl_forwarder($message, 'critical');
    }

    method alert ($message) {
      $self->_log4perl_forwarder($message, 'alert');
    }

    method emergency ($message) {
      $self->_log4perl_forwarder($message, 'emergency');
    }

    # Internal method to map Log::Handler levels to Log::Log4perl levels
    method _log4perl_forwarder ($message, $level) {
      my $log4perl_level = $INFO; # Default to INFO if unknown

      if ( $level eq 'debug' ) {
          $log4perl_level = $DEBUG;
      }
      elsif ( $level eq 'info' ) {
          $log4perl_level = $INFO;
      }
      elsif ( $level eq 'notice' ) {
          $log4perl_level = $INFO; # Log::Log4perl doesn't have a direct 'notice' level
      }
      elsif ( $level eq 'warning' ) {
          $log4perl_level = $WARN;
      }
      elsif ( $level eq 'error' ) {
          $log4perl_level = $ERROR;
      }
      elsif ( $level eq 'critical' || $level eq 'alert' || $level eq 'emergency' ) {
          $log4perl_level = $FATAL;
      }

      $self->get_logger()->log($log4perl_level, $message);
    }

  method toHashRef {
    # a base toHash implementation is necessary for Data::Printer
    # to work on child classes.
    return {};
  }

  method _isTrue {
    return
         defined($self)
      && ref($self)
      && blessed($self)
      && blessed($self) eq __CLASS__;
  }

  # Method for JSON serialization
  # a base TO_JSON implementation is necessary for Data::Printer
  # to work on child classes.
  method TO_JSON {
    my $json =
      JSON::PP->new->utf8->pretty->allow_blessed(1)
      ->convert_blessed(1)
      ->encode(__CLASS__->to_hash());
    return $json;
  }

  # Stringification method using JSON
  method as_string {
    my $json =
      JSON::PP->new->utf8->allow_blessed(1)
      ->convert_blessed(1)
      ->encode(__CLASS__->to_hash());
    return $json;
  }
}
1;

__END__
