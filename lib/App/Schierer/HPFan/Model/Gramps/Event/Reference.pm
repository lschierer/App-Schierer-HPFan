use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type;

class App::Schierer::HPFan::Model::Gramps::Event::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  ADJUST {
    if (Scalar::Util::reftype($self->role) ne 'OBJECT') {
      $self->set_role(
        App::Schierer::HPFan::Model::Gramps::Event::Role::Type->new(
          $self->role->%*
        )
      );
    }
    elsif (
      not $self->role->isa(
        'App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type')
    ) {
      $self->logger->dev_guard(sprintf(
        'unexpected type for $self->role in %s: %s',
        ref($self), ref($self->role)
      ));
    }
  }
}
1;
__END__
