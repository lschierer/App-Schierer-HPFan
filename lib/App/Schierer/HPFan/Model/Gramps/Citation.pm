use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::CustomDate;

class App::Schierer::HPFan::Model::Gramps::Citation :
  isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any );
  use Carp;

  ADJUST {

  }

  field $data : param;

  field $change         : reader //= undef;
  field $confidence     : reader //= undef;
  field $date           : reader //= undef;
  field $gramps_id      : reader //= undef;
  field $handle         : reader //= undef;
  field $page           : reader //= undef;
  field $private        : reader //= undef;
  field $source_handle  : reader //= undef;


  field $attribute_list   = [];
  field $note_list        = [];
  field $tag_list         = [];

  method attribute_list { [ $attribute_list->@* ] }
  method note_list      { [ $note_list->@* ] }
  method tag_list      { [ $tag_list->@* ] }

  ADJUST {
    $change         = $data->{change};
    $confidence     = $data->{confidence};
    $date           = App::Schierer::HPFan::Model::CustomDate->new( text => $data->{date});
    $gramps_id      = $data->{gramps_id};
    $handle         = $data->{handle};
    $page           = $data->{page};
    $private        = $data->{private};
    $source_handle  = $data->{source_handle};

    foreach my $item ($data->{attribute_list}->@*) {
      push @$attribute_list, $item;
    }

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }
  }


}
1;
__END__
