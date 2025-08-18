use v5.42.0;
use experimental qw(class);
use utf8::all;
require Date::Manip;
require App::Schierer::HPFan::Model::History::Event;

class App::Schierer::HPFan::Model::History::Gramps :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;

  # The ::Model::Gramps from which to get History
  field $gramps : param;

  # output fields
  field $events  = {};

  method events {
    return values $events->%*;
  }

  method process {
    $self->logger->info('starting processing of Gramps history.');
    foreach my $event (sort { $a->gramps_id cmp $b->gramps_id }
      values $gramps->events->%*) {
      $self->process_event($event);
    }

  }

  method process_event ($event) {
    unless ($event->type !~ /(Hogwarts Sorting|Education)/) {
      $self->logger->debug(sprintf(
        'skipping event %s with type %s',
        $event->gramps_id, $event->type
      ));
      return;
    }
    $self->logger->debug(
      sprintf('event %s has type "%s"', $event->gramps_id, $event->type));

    unless (defined($event->date->as_dm_date)) {
      $self->logger->debug(
        sprintf('skipping event %s, cannot get dm_date.', $event->gramps_id,));
      return;
    }
    $self->logger->debug(sprintf(
      'event %s has date "%s".',
      $event->gramps_id, $event->date->to_string
    ));

    if($event->type !~ /Birth/) {
      if(my $person = $self->_primary_person_for($event)) {
        $events->{$event->gramps_id} = App::Schierer::HPFan::Model::History::Event->new(
          id        => $event->gramps_id,
          origin    => 'Gramps',
          type      => 'Birth',
          blurb     => sprintf('Birth of %s', $person->display_name()),
          date_iso  => $event->date->as_dm_date->to_iso,
          date_kind => join(' ', qq( $event->date->quality_label $event->date->modifier_label )),
          sortval   => $event->date->sortval,
        );
      }
    }
  }

  method _primary_person_for ($e) {
      # via your $people_by_event index; find role 'Primary'
      for my $person ($gramps->people_by_event->{$e->handle}->@* ) {
        for my $er ($person->event_refs->@*) {
          if ($er->ref eq $e->handle && "$er->role" eq 'Primary') {
            return $person;
          }
        }
      }
      return undef;
    }


}
1;
__END__
