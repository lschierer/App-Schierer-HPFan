use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
require XML::LibXML;
require GraphViz;
require Data::Printer;
require Genealogy::Gedcom;
require Log::Log4perl;

class App::Schierer::HPFan::Model::Gedcom :isa(App::Schierer::HPFan::Logger) {
  field $gedcom_parser; # Declare the field

  ADJUST {
    # Ensure Log::Log4perl is initialized before using it in the constructor

    unless (Log::Log4perl->initialized()) {
      $self->logger = $self->get_logger();
    }

    # Initialize the Genealogy::Gedcom parser, passing $self as the logger
    $gedcom_parser = Genealogy::Gedcom->new(
        logger => $self,
    );
  }

  method parse_file ($filepath) {
      $gedcom_parser->parse_file($filepath);
  }
}
1;
__END__
