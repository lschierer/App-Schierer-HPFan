use v5.42.0;
use utf8::all;
use lib 'lib';
use lib '../PAGI-WebServer/lib';

package App::Schierer::HPFan;
use Mooish::Base -standard;
with 'WebFramework::Role::Logger';
extends 'WebFramework::App';

our $VERSION = 'v0.03.0';

sub build ($self) {
  $self->SUPER::build();

  $self->load_controller('Bookmarks');
  $self->load_controller('Family');
  $self->load_module('Middleware' => {
          Static => { root => 'public', pass_through => 1, _order => 1 },
  });

}

1;
__END__
