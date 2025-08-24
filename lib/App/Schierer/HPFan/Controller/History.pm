use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require YAML::PP;
require Scalar::Util;
require Sereal::Encoder;
require Sereal::Decoder;
require Date::Manip;
require Log::Log4perl;
require GraphViz;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;
require App::Schierer::HPFan::Model::History::YAML;

package App::Schierer::HPFan::Controller::History {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  my $logger;

  sub register($self, $app, $config) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    state $timeline_cache = {
      built  => 0,
      events => [],
    };

    $app->helper(
      timeline => sub($c) {
        unless ($timeline_cache->{built}) {
          $logger->warn('timeline cache not yet populated.');
          return [];
        }
        return $timeline_cache->{events};
      }
    );

    my $build_timeline = sub {
      return if $timeline_cache->{built};
      $logger->info('Building History timeline from Gramps…');

      my $ye = App::Schierer::HPFan::Model::History::YAML->new(
        SourceDir => $app->config('distDir')->child('history'));
      $ye->process();
      push @{ $timeline_cache->{events} }, $ye->events->@*;

      my $ge = App::Schierer::HPFan::Model::History::Gramps->new(
        gramps => $app->gramps);
      $ge->process();
      push @{ $timeline_cache->{events} }, $ge->events->@*;

      #both are now done.
      $timeline_cache->{built} = 1;

      $logger->info(
        sprintf 'History timeline built: %d items',
        scalar @{ $timeline_cache->{events} }
      );
    };

    $app->plugins->on(
      'gramps_initialized' => sub($c, $gramps) {
        $logger->debug(__PACKAGE__ . ' gramps_initialized sub start');
        $build_timeline->();
      }
    );

    if ($app->config('gramps_initialized')) {
      $logger->debug(__PACKAGE__ . ' detects gramps_initialized from config');
      $build_timeline->();
    }

    $app->routes->get('/Harrypedia/History')->to(
      controller => 'History',
      action     => 'timeline_handler',
    );

    $app->add_navigation_item({
      title => 'Timeline of Relevent Events',
      path  => '/Harrypedia/History',
      order => 1,
    });

    # Store in helper for access
    #$app->helper(history_timeline => sub { return $timeline });

  }

  sub timeline_handler ($c) {

    my $timeline = $c->timeline;
    $logger->debug(sprintf(
      'timeline_handler retrieved %s events', scalar @$timeline));

    my $timeline_view =
      App::Schierer::HPFan::View::Timeline->new(events => $timeline);
    my $svg = $timeline_view->create();

    $c->stash(svg => $svg);

    $c->stash(
      svg      => $svg,
      timeline => $timeline,
      title    => 'Timeline of Relevent Events',
      template => 'history/timeline',
      layout   => 'default'
    );

    return $c->render;
  }

}
1;
__END__
