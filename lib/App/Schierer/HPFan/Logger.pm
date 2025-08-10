use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
use namespace::autoclean;

class App::Schierer::HPFan::Logger {
# PODNAME: App::Schierer::HPFan::Logger
  use Carp;
  use Log::Log4perl;
  our $VERSION = 'v0.0.1';

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
