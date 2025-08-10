use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
require XML::LibXML;
require GraphViz;
require Data::Printer;
require App::Schierer::HPFan::Model::Gramps::Tag;
require App::Schierer::HPFan::Model::Gramps::DateHelper;
require App::Schierer::HPFan::Model::Gramps::Event;
require App::Schierer::HPFan::Model::Gramps::Surname;
require App::Schierer::HPFan::Model::Gramps::Name;
require App::Schierer::HPFan::Model::Gramps::Person;
require App::Schierer::HPFan::Model::Gramps::Family;

class App::Schierer::HPFan::Model::Gramps : isa(App::Schierer::HPFan::Logger) {
# PODNAME: App::Schierer::HPFan::Model::Gramps
  use Carp;
  use Log::Log4perl;
  our $VERSION = 'v0.0.1';

  field $gramps_export : param;

  field $tags        : reader = {};
  field $events      : reader = {};
  field $people      : reader = {};
  field $families    : reader = {};
  field $date_parser : reader =
    App::Schierer::HPFan::Model::Gramps::DateHelper->new();

  #derived fields
  field $people_by_event : reader = {};
  field $people_by_tag   : reader = {};

  ADJUST {
    # Do not assume we are passed a Path::Tiny object;
    $gramps_export = Path::Tiny::path($gramps_export);
    if (!$gramps_export->is_file) {
      $self->logger->logcroak("gramps_export $gramps_export is not a file.");
    }
  }

  method build_indexes {
    $people_by_event = {};
    for my $person (values %$people) {
      for my $h ($person->event_refs->@*) {
        push @{ $people_by_event->{$h} }, $person;
      }
      for my $t ($person->tag_refs->@*) {
        push @{ $people_by_tag->{$t} }, $person;
      }
    }
  }

  method find_person_by_handle ($handle) {
    return $people->{$handle};
  }

  method find_person_by_id ($id) {
    foreach my $person (values %{$people}) {
      if ($person->id =~ /$id/i) {
        return $person;
      }
    }
    return undef;
  }

  method find_family_by_id ($id) {
    foreach my $family (values %{$families}) {
      if ($family->id =~ /$id/i) {
        return $family;
      }
    }
    return undef;
  }

  method find_name_for_family ($family) {
    my $family_name;
    if ($family->father_ref) {
      my $father = $people->{ $family->father_ref };
      if ($father) {
        my $name = $father->primary_name();
        if ($name) {
          $family_name = $name->primary_surname();
        }
      }
    }
    elsif (scalar @{ $family->child_refs }) {
      foreach my $cr (@{ $family->child_refs }) {
        my $child = $people->{ $cr->{handle} };
        if ($child) {
          my $name = $child->primary_name();
          if ($name) {
            $family_name = $name->primary_surname();
            if (defined $family_name) {
              last;
            }
          }
        }
      }
    }
  }

  method find_events_for_person ($person) {
    my @pe;
    foreach my $handle ($person->event_refs->@*) {
      push @pe, $events->{$handle};
    }
    $self->logger->debug("retrieved list " . Data::Printer::np(@pe));
    my $date_helper = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

    # Sort events by date
    my @sorted_events = sort {
      my $date_a = $a->date;
      my $date_b = $b->date;

      # Events without dates go to the end
      return 1  if !defined $date_a && defined $date_b;
      return -1 if defined $date_a  && !defined $date_b;
      return 0  if !defined $date_a && !defined $date_b;

      # Parse dates for comparison
      my $parsed_a = $date_helper->parse_gramps_date($date_a);
      my $parsed_b = $date_helper->parse_gramps_date($date_b);

      # Handle unparseable dates
      return 1  if !defined $parsed_a && defined $parsed_b;
      return -1 if defined $parsed_a  && !defined $parsed_b;
      return 0  if !defined $parsed_a && !defined $parsed_b;

      # Compare based on date type
      my $sort_date_a = $self->_get_sort_date($parsed_a);
      my $sort_date_b = $self->_get_sort_date($parsed_b);

      return $sort_date_a cmp $sort_date_b;
    } @pe;

    return \@sorted_events;
  }

  method find_families_as_parent ($person) {
    my @pf;
    foreach my $fr (@{ $person->parent_in_refs() }) {
      push @pf, $families->{$fr};
    }
    return \@pf;
  }

  method find_families_as_child ($person) {
    my @cf;
    foreach my $fr (@{ $person->child_of_refs() }) {
      push @cf, $families->{$fr};
    }
    return \@cf;
  }

  method find_spouse ($person, $family) {
    if (ref $family ne 'App::Schierer::HPFan::Model::Gramps::Family') {
      $self->logger->error(
        'family must be a App::Schierer::HPFan::Model::Gramps::Family not '
          . ref $family);
    }
    else {
      $self->logger->debug(ref $family);
    }
    my $spouse;
    if ($person->handle eq $family->father_ref) {
      $spouse = $people->{ $family->mother_ref };
    }
    else {
      $spouse = $people->{ $family->father_ref };
    }
    return $spouse;
  }

  # Helper method to extract a sortable date from parsed date data
  method _get_sort_date($parsed_date) {
    return '' unless $parsed_date;

    if ($parsed_date->{type} eq 'single' && $parsed_date->{date}) {
      return $parsed_date->{date};
    }
    elsif ($parsed_date->{type} eq 'range' || $parsed_date->{type} eq 'span') {
      # Use start date for ranges/spans
      return $parsed_date->{start_date} || '';
    }
    elsif ($parsed_date->{type} eq 'string') {
      # String dates go after parsed dates but before undefined
      return 'zzz_' . $parsed_date->{date_string};
    }

    return '';
  }

  method compare_by_birth_date($person_a, $person_b) {
    my $birth_a = $self->get_birth_date($person_a);
    my $birth_b = $self->get_birth_date($person_b);

    # People with no birth date go to bottom
    return 1  if !defined $birth_a && defined $birth_b;
    return -1 if defined $birth_a  && !defined $birth_b;
    return 0  if !defined $birth_a && !defined $birth_b;

    # Compare actual dates
    return $birth_a cmp $birth_b;
  }

  method get_birth_date ($person) {
    foreach my $eventref (@{ $person->event_refs }) {
      my $event = $events->{$eventref};
      if ($event) {
        if ($event->type eq 'Birth') {
          return $event->date;
        }
      }
    }
  }

  method get_death_date ($person) {
    foreach my $eventref (@{ $person->event_refs }) {
      my $event = $events->{$eventref};
      if ($event) {
        if ($event->type eq 'Death') {
          return $event->date;
        }
      }
    }
  }

  method import_from_xml {

    $self->logger->debug("loading from " . $gramps_export->canonpath);
    my $dom = XML::LibXML->load_xml(location => $gramps_export->canonpath);
    my $d   = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

    # Register the namespace
    my $xc = XML::LibXML::XPathContext->new($dom);
    $xc->registerNs('g', 'http://gramps-project.org/xml/1.7.1/');

    foreach my $xTag ($xc->findnodes('//g:tags/g:tag')) {
      my $handle = $xTag->getAttribute('handle');

      if ($handle) {
        $tags->{$handle} = App::Schierer::HPFan::Model::Gramps::Tag->new(
          handle   => $xTag->getAttribute('handle'),
          name     => $xTag->getAttribute('name'),
          color    => $xTag->getAttribute('color'),
          priority => $xTag->getAttribute('priority'),
          change   => $xTag->getAttribute('change'),
        );
      }
    }
    $self->logger->info(sprintf('imported %s tags.', scalar keys %{$tags}));

    foreach my $xEvent ($xc->findnodes('//g:events/g:event')) {
      my $handle = $xEvent->getAttribute('handle');
      if ($handle) {

        my $type        = $xc->findvalue('./g:type',         $xEvent);
        my $description = $xc->findvalue('./g:description',  $xEvent);
        my $cause       = $xc->findvalue('./g:cause',        $xEvent);
        my $place_ref   = $xc->findvalue('./g:place/@hlink', $xEvent);

        my @note_refs;
        foreach my $nr ($xc->findnodes('./g:noteref/@hlink', $xEvent)) {
          push @note_refs, $nr->to_literal;
        }

        my @citationref;
        foreach my $cr ($xc->findnodes('./g:citationref/@hlink', $xEvent)) {
          push @citationref, $cr->to_literal;
        }

        # Tag references
        my @tag_refs;
        foreach my $tr ($xc->findnodes('./g:tagref/@hlink', $xEvent)) {
          push @tag_refs, $tr->to_literal;
        }

        # Object references
        my @obj_refs;
        foreach my $or ($xc->findnodes('./g:objref/@hlink', $xEvent)) {
          push @obj_refs, $or->to_literal;
        }

        $events->{$handle} = App::Schierer::HPFan::Model::Gramps::Event->new(
          handle        => $handle,
          date          => $d->import_gramps_date($xEvent, $xc),
          id            => $xEvent->getAttribute('id'),
          change        => $xEvent->getAttribute('change'),
          type          => $type,
          place_ref     => $place_ref,
          description   => $description,
          cause         => $cause,
          citation_refs => \@citationref,
          note_refs     => \@note_refs,
          tag_refs      => \@tag_refs,
        );
      }
    }
    $self->logger->info(sprintf('imported %s events.', scalar keys %{$events}));

    foreach my $xPerson ($xc->findnodes('//g:people/g:person')) {
      my $handle = $xPerson->getAttribute('handle');
      if ($handle) {
        my $id     = $xPerson->getAttribute('id');
        my $change = $xPerson->getAttribute('change');
        my $gender = $xc->findvalue('./g:gender', $xPerson) // 'U';
        $gender =~ s/^\s+|\s+$//g;

        my @names;
        foreach my $xName ($xc->findnodes('./g:name', $xPerson)) {
          my $type   = $xName->getAttribute('type') // 'Unknown';
          my $first  = $xc->findvalue('./g:first',  $xName) // '';
          my $call   = $xc->findvalue('./g:call',   $xName) // '';
          my $title  = $xc->findvalue('./g:title',  $xName) // '';
          my $nick   = $xc->findvalue('./g:nick',   $xName) // '';
          my $suffix = $xc->findvalue('./g:suffix', $xName) // '';
          my @surnames;
          foreach my $xSN ($xc->findnodes('./g:surname', $xName)) {
            my $derivation = $xSN->getAttribute('derivation') // 'Unknown';
            $derivation =~ s/^\s+|\s+$//g;
            my $value = $xSN->to_literal();
            push @surnames,
              App::Schierer::HPFan::Model::Gramps::Surname->new(
              value      => $value,
              derivation => $derivation,
              prim       => scalar @surnames ? 0 : 1,
              );
          }
          my @citationref;
          foreach my $cr ($xc->findnodes('./g:citationref/@hlink', $xName)) {
            push @citationref, $cr->to_literal;
          }
          my $alt = $xName->getAttribute('alt') // 0;
          $self->logger->debug(sprintf(
            'found name %s %s %s %s %s %s %s with %s surnames for %s',
            $type, $title,           $first,
            $call, $nick,            $suffix,
            $alt,  scalar @surnames, $id
          ));
          push @names,
            App::Schierer::HPFan::Model::Gramps::Name->new(
            type          => $type,
            first         => $first,
            call          => $call,
            surnames      => \@surnames,
            suffix        => $suffix,
            nick          => $nick,
            title         => $title,
            citation_refs => \@citationref,
            date          => $d->import_gramps_date($xName, $xc),
            alt           => $alt,
            );
        }

        my @citationref;
        foreach my $cr ($xc->findnodes('./g:citationref/@hlink', $xPerson)) {
          push @citationref, $cr->to_literal;
        }

        my @eventref;
        foreach my $hlink ($xc->findnodes('./g:eventref/@hlink', $xPerson)) {
          push @eventref, $hlink->to_literal;
        }

        my @parentin;
        foreach my $hlink ($xc->findnodes('./g:parentin/@hlink', $xPerson)) {
          push @parentin, $hlink->to_literal;
        }

        my @childof;
        foreach my $hlink ($xc->findnodes('./g:childof/@hlink', $xPerson)) {
          push @childof, $hlink->to_literal;
        }

        my @noteref;
        foreach my $hlink ($xc->findnodes('./g:noteref/@hlink', $xPerson)) {
          push @noteref, $hlink->to_literal;
        }

        my @personref;
        foreach my $hlink ($xc->findnodes('./g:personref/@hlink', $xPerson)) {
          push @personref, $hlink->to_literal;
        }

        my @tag_refs;
        foreach my $tr ($xc->findnodes('./g:tagref/@hlink', $xPerson)) {
          push @tag_refs, $tr->to_literal;
        }

        $people->{$handle} = App::Schierer::HPFan::Model::Gramps::Person->new(
          id             => $id,
          handle         => $handle,
          change         => $change,
          gender         => $gender,
          names          => \@names,
          event_refs     => \@eventref,
          child_of_refs  => \@childof,
          parent_in_refs => \@parentin,
          person_refs    => \@personref,
          note_refs      => \@noteref,
          citation_refs  => \@citationref,
          tag_refs       => \@tag_refs,
        );

      }
    }
    $self->logger->info(sprintf('imported %s people.', scalar keys %{$people}));

    foreach my $xFamily ($xc->findnodes('//g:families/g:family')) {
      my $handle = $xFamily->getAttribute('handle');
      if ($handle) {
        my $type   = $xc->findvalue('./g:rel/@type',     $xFamily);
        my $father = $xc->findvalue('./g:father/@hlink', $xFamily);
        my $mother = $xc->findvalue('./g:mother/@hlink', $xFamily);
        my $change = $xFamily->getAttribute('change');
        my $id     = $xFamily->getAttribute('id');

        my @childref;
        foreach my $cr ($xc->findnodes('./g:childref', $xFamily)) {
          my $handle     = $cr->getAttribute('hlink');
          my $father_rel = $cr->getAttribute('frel');
          my $mother_rel = $cr->getAttribute('mrel');
          my @ccr;
          foreach my $chl ($xc->findnodes('./citationref/@hlink')) {
            push @ccr, $chl->to_literal();
          }
          push @childref,
            {
            handle        => $handle,
            father_rel    => $father_rel // undef,
            mother_rel    => $mother_rel // undef,
            citation_refs => \@ccr,
            };
        }

        my @eventref;
        foreach my $hlink ($xc->findnodes('./g:eventref/@hlink', $xFamily)) {
          push @eventref, $hlink->to_literal;
        }

        my @noteref;
        foreach my $hlink ($xc->findnodes('./g:noteref/@hlink', $xFamily)) {
          push @noteref, $hlink->to_literal;
        }

        my @citationref;
        foreach my $hlink ($xc->findnodes('./g:citationref/@hlink', $xFamily)) {
          push @citationref, $hlink->to_literal;
        }

        my @tagref;
        foreach my $hlink ($xc->findnodes('./g:tagref/@hlink', $xFamily)) {
          push @tagref, $hlink->to_literal;
        }

        $families->{$handle} = App::Schierer::HPFan::Model::Gramps::Family->new(
          id            => $id,
          handle        => $handle,
          change        => $change,
          rel_type      => $type,
          father_ref    => $father,
          mother_ref    => $mother,
          event_refs    => \@eventref,
          child_refs    => \@childref,
          note_refs     => \@noteref,
          citation_refs => \@citationref,
          tag_refs      => \@tagref,
        );
      }
    }
    $self->logger->info(
      sprintf('imported %s families.', scalar keys %{$families}));
    $self->build_indexes();
  }

}
1;
__END__
