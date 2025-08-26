use v5.42;
use utf8::all;
use experimental qw(class);
require Scalar::Util;
require App::Schierer::HPFan::Model::Gramps::Repository::MediaType;

class App::Schierer::HPFan::Model::Gramps::Repository::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $data : param;

  field $call_number  : reader //= undef;
  field $media_type   : reader //= undef;
  field $private      : reader //= undef;
  field $ref          : reader //= undef;

  field $note_list = [];

  method note_list  { [ $note_list->@* ] }

  ADJUST {
    $call_number = $data->{call_number};
    $media_type  = App::Schierer::HPFan::Model::Gramps::Repository::MediaType->new($data->{media_type}->%*);
    $private     = $data->{private};
    $ref         = $data->{ref};

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }
  }

}
1;
__END__
