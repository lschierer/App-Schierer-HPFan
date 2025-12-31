package App::Schierer::HPFan::Controller::Harrypedia;
use v5.42.0;
use experimental qw(class);
use utf8::all;
use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';
use Mojo::File;
use Path::Iterator::Rule;
require YAML::PP;
require Scalar::Util;
require Sereal::Encoder;
require Sereal::Decoder;

my $logger;

has controller_name => 'Harrypedia';

sub register($c, $app, $config) {
  $c->SUPER::register($app, $config);
  $logger = Log::Log4perl->get_logger(__PACKAGE__);
  $logger->info(sprintf(
    'register function for %s.',
    __PACKAGE__
  ));

  my $distDir   = $app->config('distDir');
  my $baseRoute = '/Harrypedia';

  my $mainRoutes = $app->routes->any($baseRoute);

  $mainRoutes->get('/')
    ->to(controller => $c->controller_name, action => 'index')
    ->name("${baseRoute}_index");

  $c->build_static_routes($app, $baseRoute);
}

sub index ($c) {

  my $rp = $c->req->url->path->to_string;

# Remove trailing slash from pages
  if ($rp =~ qr{/$}) {
    my $canonical = $rp;
    $canonical =~ s{/$}{};
    if (length($canonical)) {
      return $c->redirect_to($canonical, 301);
    }
  }

  # Construct the path to the index.md file
  my $file_path = $c->app->config('distDir')
    ->child('pages')
    ->child('Harrypedia')
    ->child('index.md');

  return $c->render_markdown_file($file_path);

}

1;
__END__
