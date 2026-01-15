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

  # Load modules first
  $self->load_module('^App::Schierer::HPFan::Module::ClassLists');
  say sprintf('logo file is "%s"', $self->app->config->{config}->{modules}->{"^WebFramework::Module::SiteLogo"}->{site_logo}) if $self->env eq 'development';

  # it appears that the top one wins?
  $self->load_controller('Family');
  $self->load_controller('Person');
  $self->load_controller('History');
  $self->load_controller('Bookmarks');
  $self->load_controller('HPNOFP');
  $self->load_controller('Root');
  $self->load_module(
    'Middleware' => {
      Static => { root => 'public', pass_through => 1 },
    }
  );

}

1;
__END__
