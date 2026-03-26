package App::Schierer::HPFan::Controller::Searches;
# cspell: disable

use v5.42.0;
use Mooish::Base -standard;
extends 'WebFramework::Controller::Base';

use Future::AsyncAwait;
require Path::Tiny;
use HTML::Escape qw(escape_html);
use URI::Escape  qw(uri_escape_utf8);

has search_dir => (
  is      => 'ro',
  default => sub {
    my $self = shift;
    return Path::Tiny::path($self->app->config->{config}->{markdown_dir})->child('Searches');
  },
);

sub build ($self) {
  $self->register_routes($self->router);
}

sub register_routes ($self, $router) {
  $self->add_navigation_route('/Searches', 'Searches', { order => 25 });
  

  $router->add(
    '/Searches',
    {
      to => sub ($c, $ctx) {
        return $self->searches_index($ctx);
      },
      action => 'http.*',
    }
  );

  $self->log(info => "Registered Searches routes");
}

sub searches_index ($self, $ctx) {
  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation('/Searches');

  my $autoindex =
        $self->search_dir->is_dir
      ? $self->generate_directory_index($self->search_dir)
      : $self->generate_directory_index($self->search_dir->parent);

  $autoindex = [ sort { $a->{title} cmp $b->{title} } $autoindex->@* ];

  return $self->template(
    'page/autoindex.tt',
    {
      title        => 'Searches',
      entries      => $autoindex,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/directory-list.css'],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo,
    }
  );
}



1;
