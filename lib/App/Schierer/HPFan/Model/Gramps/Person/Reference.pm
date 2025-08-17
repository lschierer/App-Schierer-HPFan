use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Person::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  field $rel : param : reader = undef;

  ADJUST {
    $self->set_citationref_attribute_optional(1);
    $self->set_noteref_attribute_optional(1);
  }

}
1;
__END__
