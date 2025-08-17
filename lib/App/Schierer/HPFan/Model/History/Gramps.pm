use v5.42.0;
use experimental qw(class);
use utf8::all;
require Date::Manip;

class App::Schierer::HPFan::Model::History::Gramps :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;

  # The ::Model::Gramps from which to get History
  field $gramps : param;

  # output fields
  field $events : reader;

  method process {
    $self->logger->info('starting processing of Gramps history.');
    foreach my $event (sort { $a->gramps_id cmp $b->gramps_id }
      values $gramps->events->%*) {
      $self->process_event($event);
    }

  }

  method process_event ($event) {
    unless ($event->type !~ /(Hogwarts Sorting|Education)/) {
      $self->logger->debug(
        sprintf(
          'skipping event %s with type %s',
          $event->gramps_id, $event->type
        )
      );
      return;
    }
    $self->logger->debug(
      sprintf('event %s has type "%s"', $event->gramps_id, $event->type));

    unless (defined($event->date->as_dm_date)) {
      $self->logger->debug(
        sprintf('skipping event %s, cannot get dm_date.', $event->gramps_id,));
      return;
    }
    $self->logger->debug(
      sprintf(
        'event %s has date "%s".',
        $event->gramps_id, $event->date->to_string
      )
    );

  }

}
1;
__END__
