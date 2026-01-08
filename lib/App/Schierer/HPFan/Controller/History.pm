package App::Schierer::HPFan::Controller::History;

use v5.42.0;
use strict;
use warnings;
use Moo;
use experimental 'signatures';
with 'App::Schierer::HPFan::Role::Gramps';
with 'WebFramework::Role::Logger';
extends 'Thunderhorse::Controller';

use Future::AsyncAwait;
use Path::Tiny;
use Encode qw(encode_utf8);

# Load the models and view
use lib '../App-Schierer-HPFan/lib';
require App::Schierer::HPFan::Model::History::YAML;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;
require App::Schierer::HPFan::Model::Gramps;

has timeline_cache => (
    is      => 'rw',
    default => sub { { built => 0, events => [] } },
    clearer => 'clear_timeline_cache',
);

sub build ($self) {
    $self->ensure_ready();
    $self->register_routes($self->router);
}

sub register_routes ($self, $router) {
    # Add navigation route
    $self->add_navigation_route('/Harrypedia/History', 'Timeline', { order => 200 });

    # Register timeline route
    $router->add('/Harrypedia/History', {
        to => sub ($self, $ctx, @args) {
            return $self->timeline_page($ctx);
        },
        action => 'http.get',
    });
}

async sub timeline_page ($self, $ctx) {
    my $current_path = $ctx->req->path;

    # Build timeline asynchronously
    my $timeline = await $self->build_timeline();
    $self->logger->debug(sprintf('timeline_page retrieved %s events', scalar @$timeline));

    # Create Timeline view
    my $timeline_view = App::Schierer::HPFan::View::Timeline->new(events => $timeline);
    my $svg = $timeline_view->create();
    my $footnotes = $timeline_view->footnotes();

    # Render navigation
    my $navigation_html = $self->render_navigation($current_path);

    # Prepare template variables
    my $current_year = (localtime)[5] + 1900;
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

    return $self->render('history/timeline.tt', $vars);
}

async sub build_timeline ($self) {
    # Return cached if already built
    if ($self->timeline_cache->{built}) {
        $self->logger->debug('Returning cached timeline');
        return $self->timeline_cache->{events};
    }

    my @all_events;

    # Get events from YAML files asynchronously
    $self->logger->info('Building History timeline from YAML');
    my $yaml_events = App::Schierer::HPFan::Model::History::YAML->new(
        SourceDir => path('share/history')
    );
    $yaml_events->process();
    my $ye = $yaml_events->events();
    $self->logger->info(sprintf('Received %s events from YAML', scalar @$ye));
    push @all_events, @$ye;

    # Get events from Gramps database asynchronously
    $self->logger->info('Building History timeline from Gramps');
    my $gramps_events = App::Schierer::HPFan::Model::History::Gramps->new(
        gramps => $self->gramps
    );
    $gramps_events->process();
    my $ge = $gramps_events->events();
    $self->logger->info(sprintf('Received %s events from Gramps', scalar @$ge));
    push @all_events, @$ge;

    # Cache the results
    $self->timeline_cache->{events} = \@all_events;
    $self->timeline_cache->{built} = 1;

    $self->logger->info(sprintf('History timeline built: %d items', scalar @all_events));

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
