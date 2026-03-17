package App::Schierer::HPFan::Role::Gramps;
# cspell: disable
use Moo::Role;
use v5.42.0;
use utf8::all;
use experimental qw(signatures);
use Future::AsyncAwait;
use Path::Tiny;
use FindBin;
use URI::Escape qw(uri_escape_utf8);
require App::Schierer::HPFan::Model::Gramps;

has 'gramps_export' => (
  is      => 'lazy',
  default => sub { path($FindBin::Bin)->parent->child('share/data/gramps') }
);

has 'gramps_db' => (
  is      => 'lazy',
  default =>
    sub { path($FindBin::Bin)->parent->child('share/gramps/grampsdb/potter_universe/sqlite.db') }
);

my $g;
my $ready = 0;

sub gramps ($self) {
  $g //= App::Schierer::HPFan::Model::Gramps->new(
    gramps_export => $self->gramps_export,
    gramps_db     => $self->gramps_db,
  );
  return $g;
}

async sub initialize ($self) {
  return if $ready;

  $self->logger->info("⚙️  Running gramps import...");
  $self->gramps->execute_import();

  $self->logger->info("⚙️  Building gramps indexes...");
  $self->gramps->build_indexes();

  $self->logger->info("✅ gramps import completed.");
  $ready = 1;
}

async sub ensure_ready ($self) {
  return if $ready;
  await $self->initialize();
}

async sub person_house ($self, $person) {
  await $self->ensure_ready;

  my %by_handle = %{ $self->gramps->tags };

  for my $th (@{ $person->tag_list // [] }) {
    my $tag  = $by_handle{$th} or next;
    my $name = $tag->name // '';
    $name =~ s/^\s+|\s+$//g;

    return $name
      if $name =~ /^(?:Gryffindor|Hufflepuff|Ravenclaw|Slytherin)$/;

    if ($name =~ /^House:\s*(Gryffindor|Hufflepuff|Ravenclaw|Slytherin)\b/i) {
      return ucfirst lc $1;
    }
  }

  return 'Unknown House';
}

async sub person_blood_status ($self, $person) {
  await $self->ensure_ready;

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

async sub person_economic_status ($self, $person) {
  await $self->ensure_ready;

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

# Common person data methods
async sub get_all_surnames ($self) {
  await $self->ensure_ready;

  my $people = $self->gramps->people();
  my %surnames;

  for my $person (values %$people) {
    my $primary_name = $person->primary_name();
    next unless $primary_name;

    my $surname_obj = $primary_name->primary_surname();
    if ($surname_obj && $surname_obj->surname) {
      my $surname = $surname_obj->display_name;
      $surnames{$surname} = 1;
    }
  }
  my $returnRef = [];
  push @{$returnRef}, sort keys %surnames;
  return $returnRef;
}

async sub get_people_by_surname ($self, $surname) {
  await $self->ensure_ready;

  my $people = $self->gramps->people();
  my @family_members;

  for my $person (values %$people) {
    my $primary_name = $person->primary_name();
    next unless $primary_name;

    my $surname_obj    = $primary_name->primary_surname();
    my $person_surname = $surname_obj ? ($surname_obj->display_name // '') : '';

    if ($person_surname eq $surname) {
      push @family_members, $person;
    }
  }

  return \@family_members;
}

async sub get_people_with_unknown_surname ($self) {
  await $self->ensure_ready;

  my $people = $self->gramps->people();
  my @unknown;

  for my $person (values %$people) {
    my $primary_name = $person->primary_name();

    if (!$primary_name) {
      push @unknown, $person;
      next;
    }

    my $surname_obj = $primary_name->primary_surname();
    if ( !defined($surname_obj)
      || !$surname_obj->surname
      || $surname_obj->surname eq '') {
      push @unknown, $person;
    }
  }

  return \@unknown;
}

sub get_person_by_name ($self, $surname, $given_name, $suffix = '') {
  my $people = $self->gramps->people;

  for my $person (values %$people) {
    my $primary_name = $person->primary_name;
    next unless $primary_name;

    my $p_surname_obj = $primary_name->primary_surname;
    my $p_surname     = $p_surname_obj ? $p_surname_obj->display_name : '';
    my $p_given       = $primary_name->display // '';
    my $p_suffix      = $primary_name->suffix  // '';

    # Match surname and given name
    next unless ($p_surname eq $surname && $p_given eq $given_name);

    # If suffix is provided, use it for disambiguation
    if ($suffix) {
      return $person if $p_suffix eq $suffix;
    }
    else {
      # If no suffix provided, return first match (existing behavior)
      return $person;
    }
  }

  return;
}

sub link_for_person ($self, $person) {
  return '' unless $person;
  return sprintf('/Harrypedia/people/%s', $person->name_as_link_path);
}

sub display_name_for_person ($self, $person) {
  return 'Unknown' unless $person;

  # Use Person model's display_name method which includes suffix
  my $display_name = $person->display_name;
  return $display_name if $display_name;

  return 'Unknown';
}

sub prepare_person_data ($self, $person) {
  # Use the helper methods that properly handle suffixes
  my $display_name = $self->display_name_for_person($person);
  my $link         = $self->link_for_person($person);

  # Get birth and death dates
  my $events = $self->gramps->find_events_for_person($person);
  my ($birth_date, $death_date) = $self->_extract_life_dates($events);

  return {
    gramps_id    => $person->gramps_id,
    display_name => $display_name,
    link         => $link,
    gender       => $person->gender,
    birth_date   => $birth_date,
    death_date   => $death_date,
  };
}

# Extract birth and death dates from events
sub _extract_life_dates ($self, $events) {
  my ($birth_date, $death_date);

  for my $event (@$events) {
    if ($event->type eq 'Birth') {
      $birth_date = $self->_format_event_date($event);
    }
    elsif ($event->type eq 'Death') {
      $death_date = $self->_format_event_date($event);
    }
  }

  return ($birth_date, $death_date);
}

# Format event date for display
sub _format_event_date ($self, $event) {
  my $date = $event->date;
  return 'Unknown' unless $date;

  # Handle date ranges
  if ($date->is_range) {
    my $start =
      $date->start ? $self->_format_single_date($date->start) : 'Unknown';
    my $end = $date->end ? $self->_format_single_date($date->end) : 'Unknown';
    return "from $start to $end";
  }

  return $self->_format_single_date($date) || 'Unknown';
}

# Format a single date
sub _format_single_date ($self, $date) {
  return unless $date && $date->year;

  my $year  = $date->year;
  my $month = $date->month || 0;
  my $day   = $date->day   || 0;

  if ($month && $day) {
    return sprintf('%04d-%02d-%02d', $year, $month, $day);
  }
  elsif ($month) {
    return sprintf('%04d-%02d', $year, $month);
  }
  else {
    return sprintf('%04d', $year);
  }
}

1;
