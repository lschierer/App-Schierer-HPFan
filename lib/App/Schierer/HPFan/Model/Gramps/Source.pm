use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require JSON::PP;
require Data::Printer;
require App::Schierer::HPFan::Model::Gramps::Repository::Reference;

class App::Schierer::HPFan::Model::Gramps::Source :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use List::AllUtils qw( any );

  field $data : param;

  #table fields
  field $abbrev    : reader //= undef;
  field $author    : reader //= undef;
  field $change    : reader //= undef;
  field $gramps_id : reader //= undef;
  field $handle    : reader //= undef;
  field $private   : reader //= undef;
  field $pubinfo   : reader //= undef;
  field $title     : reader //= undef;

  field $attribute_list = [];
  field $note_list      = [];
  field $reporef_list   = [];
  field $tag_list       = [];

  method attribute_list { [$attribute_list->@*] }
  method note_list      { [$note_list->@*] }
  method reporef_list   { [$reporef_list->@*] }
  method tag_list       { [$tag_list->@*] }

  ADJUST {
    $abbrev    = $data->{abbrev};
    $author    = $data->{author};
    $change    = $data->{change};
    $gramps_id = $data->{gramps_id};
    $handle    = $data->{handle};
    $private   = $data->{private};
    $pubinfo   = $data->{pubinfo};
    $title     = $data->{title};

    foreach my $item ($data->{attribute_list}->@*) {
      push @$attribute_list, $item;
    }

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

    foreach my $item ($data->{reporef_list}->@*) {
      push @$reporef_list,
        App::Schierer::HPFan::Model::Gramps::Repository::Reference->new(
        data => $item);
    }

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }
  }

}
1;
__END__
