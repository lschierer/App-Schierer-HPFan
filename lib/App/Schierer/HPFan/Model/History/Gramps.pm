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

  ADJUST {
    unless($gramps && $gramps->isa('App::Schierer::HPFan::Model::Gramps')) {
      $self->logger->logcroak("gramps must be defined, and of type App::Schierer::HPFan::Model::Gramps");
    }
  }

  # output fields
  field $events = {};

  method events {
    my @out = sort {
            ($a->sortval // 0) <=> ($b->sortval // 0)
         || ($a->date_iso//'') cmp ($b->date_iso//'')
         || ($a->id//'')       cmp ($b->id//'')
      } values $events->%*;
    $self->logger->debug(sprintf('%s is returning %s events.',
    ref($self), scalar @out));
    return \@out;
  }

  method process {
    $self->logger->info('starting processing of Gramps history.');

    my @events = values $gramps->events->%*;
    $self->logger->debug(sprintf(
      'found %s events from gramps to filter.', scalar @events));

    @events = sort { $a->gramps_id cmp $b->gramps_id } @events;
    foreach my $event (@events) {
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

    if ($event->type eq  'Birth') {
      if (my $person = $self->_primary_person_for($event)) {
        my @dklparts;
        push @dklparts, $event->date->quality_label if (defined $event->date->quality_label && length($event->date->quality_label));
        push @dklparts, $event->date->modifier_label if (defined $event->date->modifier_label && length($event->date->modifier_label));
        $events->{ $event->gramps_id } =
          App::Schierer::HPFan::Model::History::Event->new(
          id        => $event->gramps_id,
          origin    => 'Gramps',
          type      => 'Birth',
          blurb     => sprintf('Birth of %s', $person->display_name()),
          date_iso  => (not $event->date->is_range) ? $event->date->as_dm_date->printf('%Y-%m-%d') : sprintf('%s - %s', $event->date->start, $event->date->end),
          date_kind => scalar @dklparts ? sprintf('(%s)', join(' ', @dklparts),) : '',
          sortval => $event->date->sortval,
          );
      }else {
        $self->logger->warn(sprintf('Birth event %s cannot be matched with a person.',
        $event->gramps_id));
      }
    }
  }

  method _primary_person_for ($e) {
    # via your $people_by_event index; find role 'Primary'
    for my $person ($gramps->people_by_event->{ $e->handle }->@*) {
      for my $er ($person->event_refs->@*) {
        if ($er->ref eq $e->handle ) {
          $self->logger->debug(sprintf('potential match: %s and %s',
          $er->ref, $e->handle));
          if($er->role eq 'Primary') {
            $self->logger->debug(sprintf(
              'returning person %s as primary for event %s based on reference %s',
              $person->gramps_id, $e->gramps_id, $er->ref,
            ));
            return $person;
          }else {
            $self->logger->debug(sprintf('er role %s indicates person %s is not the primary.',
            $er->role, $person->gramps_id));
          }
        }
      }
    }
    return undef;
  }

}
1;
__END__
