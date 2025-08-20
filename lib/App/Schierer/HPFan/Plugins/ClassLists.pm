use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Scalar::Util;
require Date::Manip;

package App::Schierer::HPFan::Plugins::ClassLists {
  use Mojo::Base 'Mojolicious::Plugin', -strict, -signatures;
  use Mojo::Util qw(xml_escape);

  my $logger;

  sub register($self, $app, $config) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    my $ClassLists = {};
    $app->plugins->on(
      'gramps_initialized' => sub($c, $gramps) {
        $logger->debug(__PACKAGE__ . ' gramps_initialized sub start');
        $ClassLists = $self->buildClassLists($app);
      }
    );

#$app->routes->get('/Harrypedia/Hogwarts/ClassLists/:year' -> [year => qr/\d{3,4}/])
#  ->to(controller => '')

    $app->helper(
      render_classlist_tables => sub ($c, $html) {

        my $table = $self->render_classlist_tables($c, $ClassLists, $html);

        return $table // '<!-- No Events Found -->';
      }
    );

  }

  sub buildClassLists($self, $app,) {
    my @events = values $app->gramps->events->%*;
    $logger->debug(
      sprintf('buildClassList found %s events to filter.', scalar @events));

    my %ClassLists;

    my @SortingEvents;
    foreach my $event (@events) {
      if ($event->type->to_string eq 'Hogwarts Sorting') {
        $logger->debug(sprintf(
          'pushing event %s with type %s',
          $event->handle, $event->type
        ));
        push @SortingEvents, $event;
      }
    }
    $logger->debug(
      sprintf('buildClassList found %s sorting events.', scalar @SortingEvents)
    );

    foreach my $event (@SortingEvents) {
      my @matches;
      my $eventDate = $event->date->to_string;
      $logger->debug(sprintf(
        'event %s has date %s and type %s.',
        $event->handle, $eventDate, $event->type
      ));

      foreach
        my $person ($app->gramps->people_by_event->{ $event->handle }->@*) {
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

  sub render_classlist_tables ($self, $c, $ClassLists, $html) {

    $logger->debug('ClassLists is ' . ref($ClassLists));
    if (scalar keys %$ClassLists == 0) {
      $logger->error('ClassLists has no keys!!');
      return undef;
    }

    my $dom = Mojo::DOM->new($html);

    # Find every <classlisttable year="YYYY">
    for my $node ($dom->find('classlisttable[year]')->each) {
      my $year = $node->attr('year') // '';

      my $matches = $ClassLists->{ sprintf('%s-09-01', $year) } // [];
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
          my $house  = xml_escape($c->person_house($_));
          my $blood  = xml_escape($c->person_blood_status($_));
          my $econ   = xml_escape($c->person_economic_status($_));

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
}
1;
__END__
