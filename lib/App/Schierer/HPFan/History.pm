package App::Schierer::HPFan::History;

use strict;
use warnings;
use Moo;
use DBI;
use Template;
use Path::Tiny;
use Encode qw(encode_utf8);

has dbh => (
    is => 'lazy',
);

has template => (
    is => 'lazy',
);

has timeline_cache => (
    is => 'rw',
    default => sub { { built => 0, events => [] } },
    clearer => 'clear_timeline_cache',
);

sub _build_dbh {
    my $self = shift;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=share/grampsdb/sqlite.db",
        "", "",
        {
            RaiseError => 1,
            sqlite_unicode => 1,
        }
    );
    return $dbh;
}

sub _build_template {
    my $self = shift;
    return Template->new({
        INCLUDE_PATH => 'templates',
        ENCODING => 'utf8',
    });
}

sub build_timeline {
    my ($self) = @_;
    
    # Initialize cache if needed
    $self->timeline_cache({ built => 0, events => [] }) unless $self->timeline_cache;
    
    return $self->timeline_cache->{events} if $self->timeline_cache->{built};
    
    # Get events from database (simplified version)
    my $sth = $self->dbh->prepare(
        "SELECT e.gramps_id, e.description, e.json_data
         FROM event e 
         WHERE e.description IS NOT NULL 
         ORDER BY e.gramps_id"
    );
    $sth->execute();
    
    my @events;
    while (my $row = $sth->fetchrow_hashref) {
        push @events, {
            id => $row->{gramps_id},
            type => 'Event',
            date => 'Unknown',
            description => $row->{description} || '',
        };
    }
    
    $self->timeline_cache->{events} = \@events;
    $self->timeline_cache->{built} = 1;
    
    # Return a copy to avoid reference issues
    return [@events];
}

sub timeline_handler {
    my ($self) = @_;
    
    # Always rebuild for now to avoid cache issues
    $self->clear_timeline_cache;
    my $timeline = $self->build_timeline;
    
    # Create simple SVG timeline (basic implementation)
    my $svg = $self->create_timeline_svg($timeline);
    my $footnotes = {};
    
    # Prepare template variables
    my $vars = {
        svg => $svg,
        timeline => $timeline || [],
        footnotes => $footnotes || {},
        title => 'Timeline of Relevant Events',
    };
    
    # Process template
    my $output = '';
    $self->template->process('history/timeline.tt', $vars, \$output)
        or die $self->template->error();
    
    return $output;
}

sub create_timeline_svg {
    my ($self, $events) = @_;
    
    # Handle undefined or empty events
    $events = [] unless defined $events;
    return '<p>No events to display</p>' unless @$events;
    
    # Simple SVG timeline - basic implementation
    my $height = 50 + (scalar @$events * 30);
    my $width = 800;
    
    my $svg = qq{<svg width="$width" height="$height" xmlns="http://www.w3.org/2000/svg">};
    $svg .= qq{<line x1="50" y1="30" x2="50" y2="} . ($height - 20) . qq{" stroke="black" stroke-width="2"/>};
    
    my $y = 50;
    for my $event (@$events) {
        $svg .= qq{<circle cx="50" cy="$y" r="5" fill="blue"/>};
        $svg .= qq{<text x="70" y="} . ($y + 5) . qq{" font-family="Arial" font-size="12">};
        $svg .= qq{$event->{id}: $event->{description}};
        $svg .= qq{</text>};
        $y += 30;
    }
    
    $svg .= qq{</svg>};
    
    return $svg;
}

1;
