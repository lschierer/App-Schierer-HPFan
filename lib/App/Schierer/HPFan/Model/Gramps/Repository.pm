use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Url;

class App::Schierer::HPFan::Model::Gramps::Repository :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $data : param;

  field $change       : reader //= undef;
  field $gramps_id    : reader //= undef;
  field $handle       : reader //= undef;
  field $name         : reader //= undef;
  field $private      : reader //= undef;
  field $type         : reader //= undef;


  field $note_list  = [];
  field $tag_list  = [];
  field $urls     = [];

  method note_list  { [ $note_list->@* ] }
  method tag_list  { [ $tag_list->@* ] }
  method urls { [ $urls->@* ] }

  ADJUST {
    $change     = $data->{change};
    $gramps_id  = $data->{gramps_id};
    $handle     = $data->{handle};
    $name       = $data->{name};
    $private    = $data->{private};
    $type       = $data->{type};

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

    foreach my $item ($data->{urls}->@*) {
      push @$tag_list, $item;
    }

    foreach my $item ($data->{urls}->@*) {
      push @$urls, App::Schierer::HPFan::Model::Gramps::Url->new($item->%*);
    }
  };


}
1;
__END__
