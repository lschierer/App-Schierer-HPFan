package App::Schierer::HPFan::Controller::History;
# cspell: disable

use v5.42.0;
use strict;
use warnings;
use Moo;
use experimental 'signatures';
with 'App::Schierer::HPFan::Role::Gramps';
extends 'Thunderhorse::Controller';

use Future::AsyncAwait;
use Path::Tiny;
use Encode qw(encode_utf8);
use CHI;

# Load the models and view
use lib '../App-Schierer-HPFan/lib';
require App::Schierer::HPFan::Model::History::YAML;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;
require App::Schierer::HPFan::Model::Gramps;

has timeline_cache => (
  is      => 'lazy',
  builder => sub {
    CHI->new(
      driver     => 'File',
      root_dir   => '/tmp/hpfan_cache',
      namespace  => 'timeline',
      serializer => 'Storable',
    );
  },
);

sub build ($self) {
  $self->ensure_ready();
  $self->register_routes($self->router);
  
  # Start background timeline builder
  $self->start_timeline_builder();
}

sub start_timeline_builder ($self) {
  # Fork a background process to build the timeline
  my $pid = fork();
  
  if (!defined $pid) {
    $self->log(error => 'Failed to fork timeline builder');
    return;
  }
  
  if ($pid == 0) {
    # Child process - build timeline and cache rendered output
    eval {
      $self->log(info => 'Background timeline builder started');
      my $events = $self->build_timeline_sync();
      
      # Render the timeline
      my $timeline_view = App::Schierer::HPFan::View::Timeline->new(events => $events);
      my $svg = $timeline_view->create();
      my $footnotes = $timeline_view->footnotes();
      
      # Cache the rendered output
      $self->timeline_cache->set('rendered', { svg => $svg, footnotes => $footnotes }, '1 day');
      $self->log(info => 'Timeline cache built successfully');
    };
    if ($@) {
      $self->log(error => "Timeline builder failed: $@");
    }
    exit(0);
  }
  
  # Parent process continues
  $self->log(info => "Started timeline builder in background (PID: $pid)");
}

sub register_routes ($self, $router) {
  # Add navigation route
  $self->add_navigation_route('/Harrypedia/History', 'Timeline',
    { order => 200 });

  # Register timeline route
  $router->add(
    '/Harrypedia/History',
    {
      to => sub ($self, $ctx, @args) {
        return $self->timeline_page($ctx);
      },
      action => 'http.*',
    }
  );
}

async sub timeline_page ($self, $ctx) {
  my $current_path = $ctx->req->path;
  my $navigation_html = $self->render_navigation($current_path);
  my $current_year = (localtime)[5] + 1900;
  
  # Try to get cached rendered timeline first
  my $cached = $self->timeline_cache->get('rendered');
  
  my ($svg, $footnotes, $timeline);
  if ($cached) {
    $self->log(debug => 'Cache hit - using cached rendered timeline');
    $svg = $cached->{svg};
    $footnotes = $cached->{footnotes};
    $timeline = [];  # Empty for template
  } else {
    $self->log(info => 'Cache miss - building timeline on demand');
    $timeline = await $self->build_timeline();
    $self->log(debug =>
      sprintf('timeline_page retrieved %s events', scalar @$timeline));

    # Create Timeline view
    my $timeline_view =
      App::Schierer::HPFan::View::Timeline->new(events => $timeline);
    $svg = $timeline_view->create();
    $footnotes = $timeline_view->footnotes();
  }

  # Prepare template variables
  my $vars = {
    svg          => $svg,
    timeline     => $timeline,
    footnotes    => $footnotes,
    title        => 'Timeline of Relevant Events',
    current_year => $current_year,
    css_files    => ['/css/navigation.css', '/css/timeline.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo(),
  };

  return $self->template('history/timeline.tt', $vars);
}

async sub build_timeline ($self) {
  my @all_events;

  # Get events from YAML files
  $self->log(info => 'Building History timeline from YAML');
  my $yaml_events = App::Schierer::HPFan::Model::History::YAML->new(
    SourceDir => path('share/history'));
  await $yaml_events->process_async();
  my $ye = $yaml_events->events();
  $self->log(info => sprintf('Received %s events from YAML', scalar @$ye));
  push @all_events, @$ye;

  # Get events from Gramps database
  $self->log(info => 'Building History timeline from Gramps');
  my $gramps_events =
    App::Schierer::HPFan::Model::History::Gramps->new(gramps => $self->gramps);
  await $gramps_events->process_async();
  my $ge = $gramps_events->events();
  $self->log(info => sprintf('Received %s events from Gramps', scalar @$ge));
  push @all_events, @$ge;

  $self->log(info =>
    sprintf('History timeline built: %d items', scalar @all_events));

  return \@all_events;
}

sub build_timeline_sync ($self) {
  my @all_events;

  # Get events from YAML files (synchronous)
  $self->log(info => 'Building History timeline from YAML (sync)');
  my $yaml_events = App::Schierer::HPFan::Model::History::YAML->new(
    SourceDir => path('share/history'));
  $yaml_events->process();
  my $ye = $yaml_events->events();
  $self->log(info => sprintf('Received %s events from YAML', scalar @$ye));
  push @all_events, @$ye;

  # Get events from Gramps database (synchronous)
  $self->log(info => 'Building History timeline from Gramps (sync)');
  my $gramps_events =
    App::Schierer::HPFan::Model::History::Gramps->new(gramps => $self->gramps);
  $gramps_events->process();
  my $ge = $gramps_events->events();
  $self->log(info => sprintf('Received %s events from Gramps', scalar @$ge));
  push @all_events, @$ge;

  $self->log(info =>
    sprintf('History timeline built: %d items', scalar @all_events));

  return \@all_events;
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Controller::History - Timeline controller for historical events

=head1 DESCRIPTION

Thunderhorse controller for displaying a timeline of historical events from both
YAML files and the Gramps genealogy database.

=cut
