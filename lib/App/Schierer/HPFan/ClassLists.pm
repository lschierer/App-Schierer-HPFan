package App::Schierer::HPFan::ClassLists;

use v5.42.0;
use strict;
use warnings;
use Moo;
use Mojo::DOM;
use Mojo::Util    qw(xml_escape);
use Log::Log4perl qw(get_logger);

has gramps => (
  is       => 'ro',
  required => 1,
);

has class_lists => (is => 'lazy',);

sub _build_class_lists {
  my ($self) = @_;

  my $logger = get_logger(__PACKAGE__);

  my @events = values %{ $self->gramps->events };
  $logger->debug(
    sprintf('buildClassList found %s events to filter.', scalar @events));

  my %ClassLists;

  # Filter for Hogwarts Sorting events
  my @SortingEvents;
  foreach my $event (@events) {
    if ($event->type->to_string eq 'Hogwarts Sorting') {
      $logger->debug(sprintf(
        'pushing event %s with type %s', $event->handle, $event->type));
      push @SortingEvents, $event;
    }
  }
  $logger->debug(
    sprintf('buildClassList found %s sorting events.', scalar @SortingEvents));

  # Build class lists by date
  foreach my $event (@SortingEvents) {
    my @matches;
    my $eventDate = $event->date->to_string;
    $logger->debug(sprintf(
      'event %s has date %s and type %s.',
      $event->handle, $eventDate, $event->type
    ));

    # Get people associated with this event
    foreach
      my $person (@{ $self->gramps->people_by_event->{ $event->handle } // [] })
    {
      push @matches, $person;
    }

    $logger->debug(sprintf(
      'buildClassList found %s people sorted in %s: %s',
      scalar @matches,
      $eventDate, join(', ', map { $_->display_name } @matches)
    ));
    $ClassLists{$eventDate} = \@matches;
  }

  return \%ClassLists;
}

sub person_house {
  my ($self, $person) = @_;

  my %by_handle = %{ $self->gramps->tags };

  for my $th (@{ $person->tag_list // [] }) {
    my $tag  = $by_handle{$th} or next;
    my $name = $tag->name // '';
    $name =~ s/^\s+|\s+$//g;

    # exact house names
    return $name
      if $name =~ /^(?:Gryffindor|Hufflepuff|Ravenclaw|Slytherin)$/;

    # "House: Gryffindor" etc.
    if ($name =~ /^House:\s*(Gryffindor|Hufflepuff|Ravenclaw|Slytherin)\b/i) {
      return ucfirst lc $1;
    }
  }

  return 'Unknown House';
}

sub person_blood_status {
  my ($self, $person) = @_;

  my %by_handle = %{ $self->gramps->tags };

  for my $th (@{ $person->tag_list // [] }) {
    my $tag  = $by_handle{$th} or next;
    my $name = $tag->name // '';
    $name =~ s/^\s+|\s+$//g;

    return $name
      if $name =~ /^(?:pure-blood|half-blood|1st gen magical|hag|non-magical)$/;
  }

  return 'Unknown Status';
}

sub person_economic_status {
  my ($self, $person) = @_;

  my %by_handle = %{ $self->gramps->tags };

  for my $th (@{ $person->tag_list // [] }) {
    my $tag  = $by_handle{$th} or next;
    my $name = $tag->name // '';
    $name =~ s/^\s+|\s+$//g;

    return $name
      if $name =~ /^(?:Lower Class|Upper Class|Middle Class)$/;
  }

  return 'Unknown';
}

sub render_classlist_tables {
  my ($self, $html) = @_;

  my $logger = get_logger(__PACKAGE__);

  my $class_lists = $self->class_lists;

  $logger->debug('ClassLists is ' . ref($class_lists));
  if (scalar keys %$class_lists == 0) {
    $logger->error('ClassLists has no keys!!');
    return $html;
  }

  my $dom = Mojo::DOM->new($html);

  # Find every <classlisttable year="YYYY">
  for my $node ($dom->find('classlisttable[year]')->each) {
    my $year = $node->attr('year') // '';

    my $matches = $class_lists->{ sprintf('%s-09-01', $year) } // [];
    $logger->debug(sprintf(
      'render_classlist_tables retrieved %s students in %s',
      scalar @$matches, $year
    ));

    # Build replacement HTML
    my $replacement;
    if (scalar @$matches) {
      my $thead = sprintf(
        '<thead class="spectrum-Table-head"><tr> %s %s %s %s %s</tr></thead>',
        '<th class="spectrum-Table-headCell">Name</th>',
        '<th class="spectrum-Table-headCell">Gender</th>',
        '<th class="spectrum-Table-headCell">House</th>',
        '<th class="spectrum-Table-headCell">Blood Status</th>',
        '<th class="spectrum-Table-headCell">Economic Status</th>',
      );
      my $tbody = join '', map {
        my $name   = xml_escape($_->display_name // '');
        my $gender = xml_escape($_->gender       // '');
        my $house  = xml_escape($self->person_house($_));
        my $blood  = xml_escape($self->person_blood_status($_));
        my $econ   = xml_escape($self->person_economic_status($_));

        qq{<tr class="spectrum-Table-row">
                    <td class="spectrum-Table-cell">$name</td>
                    <td class="spectrum-Table-cell">$gender</td>
                    <td class="spectrum-Table-cell">$house</td>
                    <td class="spectrum-Table-cell">$blood</td>
                    <td class="spectrum-Table-cell">$econ</td>
                  </tr>}
      } @$matches;

      $replacement = qq{
              <table id="$year" class="spectrum-Table spectrum-Table--sizeM spectrum-Table--compact spectrum-Table--quiet">
                $thead
                <tbody class="spectrum-Table-body">$tbody</tbody>
              </table>
            };
    }
    else {
      $replacement = sprintf(
q{<div class="classlisttable-empty">No sorting records found for %s.</div>},
        $year);
    }

    # Replace the bogus tag with the built markup
    $node->replace($replacement);
  }

  return $dom->to_string;
}

1;
