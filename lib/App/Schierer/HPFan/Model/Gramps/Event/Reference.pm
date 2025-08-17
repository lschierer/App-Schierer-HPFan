use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::RoleType;

class App::Schierer::HPFan::Model::Gramps::Event::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  ADJUST {
    if (
      ref($self->role) ne
      'App::Schierer::HPFan::Model::Gramps::Event::RoleType') {
      $self->set_role(
        App::Schierer::HPFan::Model::Gramps::Event::RoleType->new(
          $self->role->%*
        )
      );
    }
  }
}
1;
__END__
