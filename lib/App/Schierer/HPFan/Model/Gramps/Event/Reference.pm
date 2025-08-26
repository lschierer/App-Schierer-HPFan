use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type;

class App::Schierer::HPFan::Model::Gramps::Event::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;

  field $data : param;

  field $_class  : reader = undef;
  field $private : reader = 0;
  field $ref     : reader = undef;
  field $role    : reader = undef;

  field $attribute_list = [];
  field $citation_list  = [];
  field $note_list      = [];

  method attribute_list { [$attribute_list->@*] }
  method citation_list  { [$citation_list->@*] }
  method note_list      { [$note_list->@*] }

  ADJUST {
    $_class  = $data->{_class};
    $private = $data->{private};
    $ref     = $data->{ref};
    $role =
      App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type->new(
      $data->{role}->%*);
  }
}
1;
__END__
