package App::Schierer::HPFan::History;

use v5.42.0;
use strict;
use warnings;
use Moo;
with 'App::Schierer::HPFan::Role::Gramps';
use Future::AsyncAwait;
use Path::Tiny;
use Encode        qw(encode_utf8);
use Log::Log4perl qw(get_logger);

# Load the models and view
use lib '../App-Schierer-HPFan/lib';
require App::Schierer::HPFan::Model::History::YAML;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;
require App::Schierer::HPFan::Model::Gramps;

has template => (
  is       => 'ro',
  required => 1,
);

has navigation => (
  is       => 'ro',
  required => 1,
);

async sub register_routes ($self, $nav, $router) {
  $router->get(
    '/Harrypedia/History' => async sub {
      my ($scope, $receive, $send) = @_;

      my $html  = $self->timeline_handler;
      my $bytes = encode_utf8($html);

      await $send->({
        type    => 'http.response.start',
        status  => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
      });
      await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
      });
    }
  );
}

has timeline_cache => (
  is      => 'rw',
  default => sub { { built => 0, events => [] } },
  clearer => 'clear_timeline_cache',
);

sub build_timeline {
  my ($self) = @_;

  my $logger = get_logger(__PACKAGE__);

  # Return cached if already built
  if ($self->timeline_cache->{built}) {
    $logger->debug('Returning cached timeline');
    return $self->timeline_cache->{events};
  }

  my @all_events;

  # Get events from YAML files
  $logger->info('Building History timeline from YAML');
  my $yaml_events = App::Schierer::HPFan::Model::History::YAML->new(
    SourceDir => path('share/history'));
  $yaml_events->process();
  my $ye = $yaml_events->events;
  $logger->info(sprintf('Received %s events from YAML', scalar @$ye));
  push @all_events, @$ye;

  # Get events from Gramps database
  $logger->info('Building History timeline from Gramps');
  my $gramps_events =
    App::Schierer::HPFan::Model::History::Gramps->new(gramps => $self->gramps);
  $gramps_events->process();
  my $ge = $gramps_events->events;
  $logger->info(sprintf('Received %s events from Gramps', scalar @$ge));
  push @all_events, @$ge;

  # Cache the results
  $self->timeline_cache->{events} = \@all_events;
  $self->timeline_cache->{built}  = 1;

  $logger->info(
    sprintf('History timeline built: %d items', scalar @all_events));

  return \@all_events;
}

sub timeline_handler {
  my ($self) = @_;

  my $logger = get_logger(__PACKAGE__);

  # Build timeline
  my $timeline = $self->build_timeline;
  $logger->debug(
    sprintf('timeline_handler retrieved %s events', scalar @$timeline));

  # Create Timeline view
  my $timeline_view =
    App::Schierer::HPFan::View::Timeline->new(events => $timeline);
  my $svg       = $timeline_view->create();
  my $footnotes = $timeline_view->footnotes;

  # Render navigation
  my $navigation_html = $self->navigation->render('/Harrypedia/History');

  # Prepare template variables
  my $current_year = (localtime)[5] + 1900;
  my $vars         = {
    svg          => $svg,
    timeline     => $timeline,
    footnotes    => $footnotes,
    title        => 'Timeline of Relevant Events',
    current_year => $current_year,
    css_files    => ['/css/navigation.css', '/css/timeline.css'],
    sidebar      => 1,
    navigation   => $navigation_html,
  };

  # Render with layout
  my $html = $self->template->render('history/timeline.tt', $vars,
    { layout => 'layouts/default.tt' });

  return $html;
}

1;
