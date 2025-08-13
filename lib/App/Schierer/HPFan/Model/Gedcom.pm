use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
require XML::LibXML;
require GraphViz;
require Data::Printer;
require Gedcom;
require Log::Log4perl;

class App::Schierer::HPFan::Model::Gedcom : isa(App::Schierer::HPFan::Logger) {
  field $gedcom_parser;
  field $filename : param;
  use Carp;

  ADJUST {

    # Initialize the Genealogy::Gedcom parser, passing $self as the logger
    $gedcom_parser = Gedcom->new(
      gedcom_file     => $filename,
      grammar_version => "5.5.1",
      read_only       => 1,
    );
  }

  method run {
    local $SIG{__WARN__} = sub {
      my $msg = shift;
      chomp $msg;
      $self->warning($msg);    # Log with your Logger instead
    };

    if ($gedcom_parser->validate()) {
      $self->info("import successful!");
    }
    else {
      $self->warning("import validation falied!");
    }

  }
}
1;
__END__
