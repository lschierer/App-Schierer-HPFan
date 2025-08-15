use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Source::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;


  method _import {
    $self->SUPER::_import;

  }
}
1;
__END__
