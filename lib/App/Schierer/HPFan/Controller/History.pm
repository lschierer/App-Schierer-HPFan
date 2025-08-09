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

package App::Schierer::HPFan::Controller::History {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  sub register($self, $app, $config) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(__PACKAGE__ . "Register method start");

    # Build the unified timeline
    my $timeline = $self->_build_timeline($app);

    # Store in helper for access
    $app->helper(history_timeline => sub { return $timeline });

    $app->routes->get('/Harrypedia/History')->to(
      controller => 'History',
      action     => 'timeline_handler',
    );

    $app->add_navigation_item({
      title => 'Timeline of Relevent Events',
      path  => '/Harrypedia/History',
      order => 1,
    });

  }

  sub timeline_handler ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);

    my $timeline = $c->history_timeline;

    $c->stash(
      timeline => $timeline,
      title    => 'Timeline of Relevent Events',
      template => 'history/timeline',
      layout   => 'default'
    );

    return $c->render;
  }

  sub _build_timeline($self, $app) {
    my $logger      = Log::Log4perl->get_logger(__PACKAGE__);
    my $history_dir = $app->config('distDir')->child('history');

    my @all_events;

    # Find all YAML files in the history directory
    my $rule = Path::Iterator::Rule->new;
    my $iter = $rule->file->name(qr/\.yaml$/)->iter($history_dir);

    while (my $file_path = $iter->()) {
      $logger->debug("Processing history file: $file_path");

      my $events = $self->_process_history_file($file_path);
      push @all_events, @$events if $events;
    }

    # Sort events by date
    @all_events = sort { $a->{date}->cmp($b->{date}); } @all_events;

    $logger->info(
      sprintf("Built timeline with %d total events", scalar @all_events));
    return \@all_events;
  }

  sub _process_history_file($self, $file_path) {
    my $logger   = Log::Log4perl->get_logger(__PACKAGE__);
    my $file     = Mojo::File->new($file_path);
    my $filename = $file->basename('.yaml');

    # Parse the YAML
    my $yaml = YAML::PP->new;
    my $data;

    eval { $data = $yaml->load_file($file_path); };

    if ($@) {
      $logger->error("Failed to parse YAML file $file_path: $@");
      return [];
    }

    unless ($data && $data->{events} && ref($data->{events}) eq 'ARRAY') {
      $logger->warn("No events array found in $file_path");
      return [];
    }

    my @events;

    foreach my $event (@{ $data->{events} }) {
      # Add file-based date info if event doesn't have its own date

      my $eventDate;
      $eventDate = $event->{date} if exists $event->{date};
      unless (exists $event->{date}) {
        if ($filename !~ /\d{2}th/ and $filename =~ /^\d+$/) {
          $eventDate = sprintf('%04d', $filename);
        }
        else {
          $eventDate = $filename;
        }
      }
      $logger->debug("eventDate is $eventDate");

      my $dm = new Date::Manip::Date;
      $dm->config("language",         "English");
      $dm->config("Use_POSIX_Printf", 1);
      $dm->config("SetDate",          "zone,UTC");

      my $err;
      if ($eventDate =~ /(\d{1,2})th/) {
        # Century only - very truncated
        my $century = 100 * ($1 - 1);
        $logger->debug("Century String detected: $century");
        $err = $dm->parse($century);
      }
      elsif ($eventDate =~ /(\d+)-(\d+)-(\d+)/
        or $eventDate =~ /(\d+)-(\d+)/
        or $eventDate =~ /^(\d+)/) {
        $eventDate =~ s/^(\d{3})$/0$1/;
        $eventDate =~ s/^(\d{3})-(.+)$/0$1-$2/;

        $err = $dm->parse($eventDate);
      }
      else {
        $logger->error(sprintf(
          'unknown date format for event in %s!! %s',
          $filename, Data::Printer::np($event)
        ));
        $err = $dm->parse('%Y-%m-%d', '9999-12-31');
      }

      # Check if parsing was successful
      if ($err) {
        $logger->error("Date Parsing Failed: $err");
        $dm->parse('9999-12-31');    # Fallback
      }

      $event->{date} = $dm;
      $logger->debug(sprintf(
        'event date is now type "%s" and formats as "%s"',
        ref $event->{date},
        $event->{date}->printf('%Y-%m-%d') // 'UNKNOWN'
      ));

      # Add source file for debugging
      $event->{_source_file} = $filename;

      push @events, $event;
    }

    return \@events;
  }

}
1;
__END__
