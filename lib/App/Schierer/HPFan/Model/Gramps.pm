use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
require XML::LibXML;
require GraphViz;
require DBI;
require DBD::SQLite;
require Data::Printer;
require App::Schierer::HPFan::Model::Gramps::Tag;
require App::Schierer::HPFan::Model::Gramps::DateHelper;
require App::Schierer::HPFan::Model::Gramps::Event;
require App::Schierer::HPFan::Model::Gramps::Surname;
require App::Schierer::HPFan::Model::Gramps::Name;
require App::Schierer::HPFan::Model::Gramps::Person;
require App::Schierer::HPFan::Model::Gramps::Family;
require App::Schierer::HPFan::Model::Gramps::Citation;
require App::Schierer::HPFan::Model::Gramps::Source;
require App::Schierer::HPFan::Model::Gramps::Repository;
require App::Schierer::HPFan::Model::Gramps::Repository::Reference;
require App::Schierer::HPFan::Model::Gramps::Note;

class App::Schierer::HPFan::Model::Gramps : isa(App::Schierer::HPFan::Logger) {
# PODNAME: App::Schierer::HPFan::Model::Gramps
  use Carp;
  use Log::Log4perl;
  use DBD::SQLite::Constants qw/:dbd_sqlite_string_mode/;
  our $VERSION = 'v0.0.1';

  field $gramps_export : param;
  field $gramps_db     : param;
  field $dbh;

  field $tags         : reader = {};
  field $events       : reader = {};
  field $people       : reader = {};
  field $families     : reader = {};
  field $citations    : reader = {};
  field $sources      : reader = {};
  field $notes        : reader = {};
  field $repositories : reader = {};
  field $date_parser  : reader =
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
    $gramps_db = Path::Tiny::path($gramps_db);
    if (!$gramps_db->is_file) {
      $self->logger->logcroak("gramps_db $gramps_db is not a file.");
    }
    else {
      $dbh = DBI->connect(
        "dbi:SQLite:$gramps_db",
        undef, undef,
        {
          RaiseError => 1,
          AutoCommit => 1,    #fallback just in case
        }
      );
      $self->logger->logcroak(
        "unsuccessfull connecting to $gramps_db. error: " . $DBI::errstr)
        unless ($dbh);
      $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK;
      # One-time-ish setup (safe if repeated)
      $dbh->do('PRAGMA journal_mode=WAL');     # persistent per DB
      $dbh->do('PRAGMA synchronous=NORMAL');   # performance tradeoff ok for dev
      $dbh->do('PRAGMA temp_store=MEMORY');

      # Now forbid writes on THIS connection:
      $dbh->do('PRAGMA query_only=ON');        # connection-level read-only
          # Optional: longer busy timeout to handle writer checkpoints
      $dbh->do('PRAGMA busy_timeout=3000');
    }
  }

  method fetch_change_for_handles (@handles) {
    return [] unless @handles;
    my $in = join ',', ('?') x @handles;
    return $dbh->selectall_arrayref(
      "SELECT handle, change FROM event WHERE handle IN ($in)",
      { Slice => {} }, @handles) // [];
  }

  method build_indexes {
    # reset both maps
    $people_by_event = {};
    $people_by_tag   = {};

    # iterate the actual people map on the object
    for my $person (values %{ $self->people }) {

      # ---- events → people
      my %seen_e;
      for my $eref (@{ $person->event_refs // [] }) {
        # $eref is App::…::Event::Reference
        my $eh = eval { $eref->ref } // '';
        next unless length $eh;
        next if $seen_e{$eh}++;
        push @{ ($people_by_event->{$eh} //= []) }, $person;
      }

      # ---- tags → people
      # if your person->tag_refs returns objects too, extract their handles;
      # otherwise if they’re already strings, this is fine
      my %seen_t;
      for my $tref ($person->tag_refs->@*) {
        my $th =
             ref($tref)
          && ref($tref) eq 'HASH'
          ? ($tref->{ref} // '')
          : "$tref";    # already a handle
        next unless length $th;
        next if $seen_t{$th}++;
        push @{ ($people_by_tag->{$th} //= []) }, $person;
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
    if ($family->father_handle) {
      my $father = $people->{ $family->father_handle };
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
    $self->logger->debug(sprintf('find_events_for_person called for "%s"', $person->gramps_id));

    my @pe;
    foreach my $cr ($person->event_refs->@*) {
      my $event = $events->{$cr->ref};
      $self->logger->debug(sprintf('found event "%s" for handle "%s".',
      $event? $event->handle : "Undefined", $cr->ref));
      push @pe, $event if($event);
    }
    $self->logger->debug("retrieved list " . Data::Printer::np(@pe));
    my $date_helper = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

    # Sort events by date
    my @sorted_events = sort @pe;

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
    if ($person->handle eq $family->father_handle) {
      $spouse = $people->{ $family->mother_handle };
    }
    else {
      $spouse = $people->{ $family->father_handle };
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
    $self->logger->debug(sprintf('finding birthday for %s', $person->gramps_id));
    my $br = $person->birth_ref_index;
    if($br >= 0 && scalar @{$person->event_refs} >= $br) {
      my $er = $person->event_refs->[$br];
      my $event = $events->{$er->ref};
      if($event){
        $self->logger->debug(sprintf('event type "%s" id "%s" at specified index "%s"',
        $event->type, $event->gramps_id, $br));
        if($event->type eq 'Birth') {
          $self->logger->debug(sprintf('returning event %s as birthday', $event->gramps_id));
          return $event;
        } else {
          $self->logger->error("found bad event at index $br: " . Data::Printer::np($event));
        }
      }
    }else {
      $self->logger->warn(sprintf('No birth index for person %s present', $person->gramps_id));
    }
    return 'Unknown';
  }

  method get_death_date ($person) {
    $self->logger->debug(sprintf('finding deathday for %s', $person->gramps_id));
    my $br = $person->death_ref_index;
    if($br >= 0 && scalar @{$person->event_refs} >= $br) {
      my $er = $person->event_refs->[$br];
      my $event = $events->{$er->ref};
      if($event){
        $self->logger->debug(sprintf('event type "%s" id "%s" at specified index "%s"',
        $event->type, $event->gramps_id, $br));
        if($event->type eq 'Death') {
          $self->logger->debug(sprintf('returning event %s as deathday', $event->gramps_id));
          return $event;
        } else {
          $self->logger->error("found bad event at index $br: " . Data::Printer::np($event));
        }
      }
    }else {
      $self->logger->warn(sprintf('No death index for person %s present', $person->gramps_id));
    }
    return 'Unknown';
  }

  method execute_import {
    $self->logger->info(
      'starting Gramps Import from XML file: ' . $gramps_export->canonpath);
    my $dom = XML::LibXML->load_xml(location => $gramps_export->canonpath);
    my $d   = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

    # Register the namespace
    my $xc = XML::LibXML::XPathContext->new($dom);
    $xc->registerNs('g', 'http://gramps-project.org/xml/1.7.1/');

    $self->_import_citations($xc);
    $self->_import_events();
    $self->_import_families();
    $self->_import_notes($xc);
    $self->_import_people();
    $self->_import_repositories($xc);
    $self->_import_sources($xc);
    $self->_import_tags();
  }

  method _import_people () {
    my $all_entries = $dbh->selectcol_arrayref("SELECT handle FROM person");

    foreach my $handle (@$all_entries) {
      my $row = $dbh->selectrow_hashref("SELECT * FROM person WHERE handle = ?",
        undef, $handle,);

      $people->{$handle} =
        App::Schierer::HPFan::Model::Gramps::Person->new($row->%*);
      $people->{$handle}->set_dbh($dbh);
      $people->{$handle}->parse_json_data;
    }

    $self->logger->info(sprintf('imported %s people.', scalar keys %{$people}));
  }

  method _import_families () {
    my $all_entries = $dbh->selectcol_arrayref("SELECT handle FROM family");

    foreach my $handle (@$all_entries) {
      my $row = $dbh->selectrow_hashref("SELECT * FROM family WHERE handle = ?",
        undef, $handle,);

      $families->{$handle} =
        App::Schierer::HPFan::Model::Gramps::Family->new($row->%*);
      $families->{$handle}->set_dbh($dbh);
      $families->{$handle}->parse_json_data;
    }
    $self->logger->info(
      sprintf('imported %s families.', scalar keys %{$families}));
  }

  method _import_tags () {
    my $all_entries = $dbh->selectcol_arrayref("SELECT handle FROM tag");

    foreach my $handle (@$all_entries) {
      my $row = $dbh->selectrow_hashref("SELECT * FROM tag WHERE handle = ?",
        undef, $handle,);

      $tags->{$handle} =
        App::Schierer::HPFan::Model::Gramps::Tag->new($row->%*);
      $tags->{$handle}->set_dbh($dbh);
      $tags->{$handle}->parse_json_data;
    }
    $self->logger->info(sprintf('imported %s tags.', scalar keys %{$tags}));
  }

  method _import_citations ($xc) {
    my $d = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    foreach my $xItem ($xc->findnodes('//g:citations/g:citation')) {
      my $handle = $xItem->getAttribute('handle');
      if ($handle) {
        $citations->{$handle} =
          App::Schierer::HPFan::Model::Gramps::Citation->new(
          XPathContext => $xc,
          XPathObject  => $xItem,
          );

      }
    }
    $self->logger->info(
      sprintf('imported %s citations.', scalar keys %{$citations}));
  }

  method _import_sources ($xc) {
    my $d = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    foreach my $xItem ($xc->findnodes('//g:sources/g:source')) {
      my $handle = $xItem->getAttribute('handle');
      if ($handle) {
        $sources->{$handle} = App::Schierer::HPFan::Model::Gramps::Source->new(
          XPathContext => $xc,
          XPathObject  => $xItem,
        );

      }
    }
    $self->logger->info(
      sprintf('imported %s sources.', scalar keys %{$sources}));
  }

  method _import_notes ($xc) {
    my $d = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    foreach my $xItem ($xc->findnodes('//g:notes/g:note')) {
      my $handle = $xItem->getAttribute('handle');
      if ($handle) {
        $notes->{$handle} = App::Schierer::HPFan::Model::Gramps::Note->new(
          XPathContext => $xc,
          XPathObject  => $xItem,
        );

      }
    }
    $self->logger->info(sprintf('imported %s notes.', scalar keys %{$sources}));
  }

  method _import_repositories ($xc) {
    my $d = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
    foreach my $xItem ($xc->findnodes('//g:repositories/g:repository')) {
      my $handle = $xItem->getAttribute('handle');
      if ($handle) {
        $repositories->{$handle} =
          App::Schierer::HPFan::Model::Gramps::Repository->new(
          XPathContext => $xc,
          XPathObject  => $xItem,
          );
      }
    }
    $self->logger->info(
      sprintf('imported %s repositories.', scalar keys %{$repositories}));
  }

  method _import_events () {
    my $all_entries = $dbh->selectcol_arrayref("SELECT handle FROM event");

    foreach my $handle (@$all_entries) {
      my $row = $dbh->selectrow_hashref("SELECT * FROM event WHERE handle = ?",
        undef, $handle,);
      $events->{$handle} =
        App::Schierer::HPFan::Model::Gramps::Event->new($row->%*);
      $events->{$handle}->set_dbh($dbh);
      $events->{$handle}->parse_json_data;
    }

    $self->logger->info(sprintf('imported %s events.', scalar keys %{$events}));
  }

}
1;
__END__
