package App::Schierer::HPFan::Module::ClassLists;

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
with 'App::Schierer::HPFan::Role::Gramps';
with 'WebFramework::Role::Logger';
extends 'Thunderhorse::Module';
use Future::AsyncAwait;

use Mojo::DOM;
use HTML::Escape qw(escape_html);

has class_lists => (is => 'lazy');

sub _build_class_lists ($self) {
  my @events = values %{ $self->gramps->events };
  $self->logger->debug(
    sprintf('buildClassList found %s events to filter.', scalar @events));

  my %ClassLists;

  # Filter for Hogwarts Sorting events
  my @SortingEvents;
  foreach my $event (@events) {
    if ($event->type->to_string eq 'Hogwarts Sorting') {
      $self->logger->debug(sprintf(
        'pushing event %s with type %s', $event->handle, $event->type));
      push @SortingEvents, $event;
    }
  }
  $self->logger->debug(
    sprintf('buildClassList found %s sorting events.', scalar @SortingEvents));

  # Build class lists by date
  foreach my $event (@SortingEvents) {
    my @matches;
    my $eventDate = $event->date->to_string;
    $self->logger->debug(sprintf(
      'event %s has date %s and type %s.',
      $event->handle, $eventDate, $event->type
    ));

    # Get people associated with this event
    foreach
      my $person (@{ $self->gramps->people_by_event->{ $event->handle } // [] })
    {
      push @matches, $person;
    }

    $self->logger->debug(sprintf(
      'buildClassList found %s people sorted in %s: %s',
      scalar @matches,
      $eventDate, join(', ', map { $_->display_name } @matches)
    ));
    $ClassLists{$eventDate} = \@matches;
  }

  return \%ClassLists;
}

sub build ($self) {
  $self->ensure_ready();

  weaken $self;

  # Register the render_classlist_tables helper method for controllers
  $self->add_method(
    controller => render_classlist_tables => async sub ($controller, $html) {
      return await $self->_render_classlist_tables($html);
    }
  );
}

async sub _render_classlist_tables ($self, $html) {
  my $class_lists = $self->class_lists;

  $self->logger->debug('ClassLists is ' . ref($class_lists));
  if (scalar keys %$class_lists == 0) {
    $self->logger->error('ClassLists has no keys!!');
    return $html;
  }

  my $dom = Mojo::DOM->new($html);

  # Find every <classlisttable year="YYYY"> or <ClassListTable year="YYYY">
  # Note: Mojo::DOM normalizes HTML tag names to lowercase
  for my $node ($dom->find('classlisttable[year]')->each) {
    my $year = $node->attr('year') // '';

    my $matches = $class_lists->{ sprintf('%s-09-01', $year) } // [];
    $self->logger->debug(sprintf(
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

      # Process each person asynchronously to get their data
      my @rows;
      for my $person (@$matches) {
        my $name   = escape_html($person->display_name // '');
        my $gender = escape_html($person->gender       // '');
        my $house  = escape_html(await $self->person_house($person));
        my $blood  = escape_html(await $self->person_blood_status($person));
        my $econ   = escape_html(await $self->person_economic_status($person));

        push @rows, qq{<tr class="spectrum-Table-row">
                    <td class="spectrum-Table-cell">$name</td>
                    <td class="spectrum-Table-cell">$gender</td>
                    <td class="spectrum-Table-cell">$house</td>
                    <td class="spectrum-Table-cell">$blood</td>
                    <td class="spectrum-Table-cell">$econ</td>
                  </tr>};
      }
      my $tbody = join '', @rows;

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

__END__

=head1 NAME

App::Schierer::HPFan::Module::ClassLists - Thunderhorse module for rendering Hogwarts class lists

=head1 DESCRIPTION

This module builds class lists from Gramps genealogical data (specifically Hogwarts
Sorting events) and provides a helper method to post-process HTML content, replacing
custom <classlisttable year="YYYY"> tags with rendered HTML tables.

=head1 REGISTERED METHODS

=head2 render_classlist_tables($html)

Post-processes HTML content, replacing <classlisttable year="YYYY"> tags with
tables showing students sorted in that year, including their house, blood status,
and economic status.

=cut
