use v5.42.0;
use experimental qw(class);
use utf8::all;
require Date::Manip;
require App::Schierer::HPFan::Model::History::Event;
require App::Schierer::HPFan::Model::Gramps::Note;
require App::Schierer::HPFan::View::Markdown;

class App::Schierer::HPFan::Model::History::Gramps :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;

  # The ::Model::Gramps from which to get History
  field $gramps : param;
  field $mv = App::Schierer::HPFan::View::Markdown->new();

  ADJUST {
    unless ($gramps && $gramps->isa('App::Schierer::HPFan::Model::Gramps')) {
      $self->logger->logcroak(
        "gramps must be defined, ' .
    'and of type App::Schierer::HPFan::Model::Gramps"
      );
    }
  }

  # output fields
  field $events = {};

  method events {
    my @out = sort {
           ($a->sortval // 0) <=> ($b->sortval // 0)
        || ($a->date->toISO // '') cmp($b->date->toISO // '')
        || ($a->id // '') cmp($b->id // '')
    } values $events->%*;
    $self->logger->debug(sprintf(
      '%s is returning %s events.', ref($self), scalar @out));
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

    unless (defined($event->date)
      && (defined($event->date->year) or $event->date->is_range)) {
      $self->logger->debug(
        sprintf('skipping event %s, cannot get year.', $event->gramps_id,));
      return;
    }
    if ($event->date->is_range) {
      unless (defined($event->date)
        and $event->date->isa('App::Schierer::HPFan::Model::Gramps::GrampsDate')
        and (defined($event->date->start) or defined($event->date->end))) {
        $self->logger->debug(sprintf(
          'skipping event %s,'
            . ' must have either at least start or end for a range',
          $event->gramps_id
        ));
        return;
      }
    }
    $self->logger->debug(sprintf(
      'event %s has date "%s".',
      $event->gramps_id, $event->date->to_string
    ));

    if ($event->type eq 'Birth') {
      $self->process_birth_event($event);
    }
    elsif ($event->type eq 'Death') {
      $self->process_death_event($event);
    }
  }

  method process_birth_event ($e) {
    my @citations;
    my @description;
    if (my $person = $self->_primary_person_for($e)) {

      # handle date
      my @dklparts;
      push @dklparts, $e->date->qualifiers
        if (defined $e->date->qualifiers && length($e->date->qualifiers));
      push @dklparts, $e->date->modifiers
        if (defined $e->date->modifiers
        && length($e->date->modifiers));

      # set up description
      push @description, $e->description
        if (defined($e->description) && length($e->description));
      my $note_text = $self->_notes_for_event($e);
      push @description, $note_text->@* if (scalar @$note_text);

      # final object
      $events->{ $e->gramps_id } =
        App::Schierer::HPFan::Model::History::Event->new(
        id          => $e->gramps_id,
        blurb       => sprintf('Birth of %s', $person->display_name()),
        description => $mv->format_string(
          join('\n', @description),
          {
            asXHTML      => 1,
            sizeTemplate => 'timeline',
          }
        ),
        event_class => 'magical',
        origin      => 'Gramps',
        sortval     => $e->date->sortval,
        type        => 'Birth',
        );
      $events->{ $e->gramps_id }->set_date($e->date);
    }
    else {
      $self->logger->warn(sprintf(
        'Birth event %s cannot be matched with a person.',
        $e->gramps_id));
    }
  }

  method process_death_event ($e) {
    if (my $person = $self->_primary_person_for($e)) {
      my @citations;
      my @description;

      # set up date
      my @dklparts;
      push @dklparts, $e->date->qualifiers
        if (defined $e->date->qualifiers && length($e->date->qualifiers));
      push @dklparts, $e->date->modifiers
        if (defined $e->date->modifiers
        && length($e->date->modifiers));

      # set up description
      push @description,
        $mv->format_string(
        $e->description,
        {
          asXHTML      => 1,
          sizeTemplate => 'timeline',
        }
        ) if (defined($e->description) && length($e->description));

      my $note_text = $self->_notes_for_event($e);
      push @description, $note_text->@* if (scalar @$note_text);

      # final object
      $events->{ $e->gramps_id } =
        App::Schierer::HPFan::Model::History::Event->new(
        id          => $e->gramps_id,
        origin      => 'Gramps',
        type        => 'Death',
        event_class => 'magical',
        blurb       => sprintf('Death of %s', $person->display_name()),
        sortval     => $e->date->sortval,
        description => join('', @description),
        );
      $events->{ $e->gramps_id }->set_date($e->date);
    }
    else {
      $self->logger->warn(sprintf(
        'Death event %s cannot be matched with a person.',
        $e->gramps_id));
    }
  }

  method _notes_for_event ($e) {
    my @return;
    foreach my $nr ($e->note_refs->@*) {
# TODO some note references have other interesting properties beyond being a handle
      if (Scalar::Util::reftype($nr) eq 'OBJECT'
        && $nr->isa('App::Schierer::HPFan::Model::Gramps::Note::Reference')) {
        my $note =
          App::Schierer::HPFan::Model::Gramps::Note->new(handle => $nr->ref);
        $note->set_dbh($e->dbh);
        if ($note->isa('App::Schierer::HPFan::Model::Gramps::Note')) {
          if (defined($note->gramps_id) && length($note->gramps_id)) {
            push @return, $note->text->raw
              if (defined($note->text->raw) && length($note->text->raw));
            $self->logger->debug(sprintf(
              'pushed new note to description for %s', $e->gramps_id));
            foreach my $cr ($note->citation_refs->@*) {
              #todo handle citations.
            }
          }
        }
        else {
          $self->logger->error(sprintf(
            'note is not a Note object, it shows as ref %s blessed %s.',
            Scalar::Util::reftype($note),
            Scalar::Util::blessed($note)
          ));
        }
      }
      else {
        $self->logger->error(sprintf(
'nr is not a Note::Reference object, it shows as ref %s blessed %s. isa %s',
          Scalar::Util::reftype($nr) // 'Undefined',
          Scalar::Util::blessed($nr) // 'Undefined',
          $nr->isa('App::Schierer::HPFan::Model::Gramps::Note::Reference')
          ? 'true'
          : 'false',
        ));
      }
    }
    return \@return;
  }

  method _primary_person_for ($e) {
    # via your $people_by_event index; find role 'Primary'
    for my $person ($gramps->people_by_event->{ $e->handle }->@*) {
      for my $er ($person->event_refs->@*) {
        if ($er->ref eq $e->handle) {
          $self->logger->debug(sprintf(
            'potential match: %s and %s', $er->ref, $e->handle));
          if ($er->role eq 'Primary') {
            $self->logger->debug(sprintf(
'returning person %s as primary for event %s based on reference %s',
              $person->gramps_id, $e->gramps_id, $er->ref,
            ));
            return $person;
          }
          else {
            $self->logger->debug(sprintf(
              'er role %s indicates person %s is not the primary.',
              $er->role, $person->gramps_id
            ));
          }
        }
      }
    }
    return undef;
  }

}
1;
__END__
