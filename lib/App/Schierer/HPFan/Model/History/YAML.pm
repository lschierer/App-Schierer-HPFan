use v5.42.0;
use experimental qw(class);
use utf8::all;

require App::Schierer::HPFan::Model::History::Event;
require YAML::PP;
require Path::Tiny;
require Path::Iterator::Rule;
require Date::Calc::Object;


class App::Schierer::HPFan::Model::History::YAML :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Date::Calc qw(Date_to_Days);
  use Readonly;

  # The ::Model::Gramps from which to get History
  field $SourceDir : param;
  field $mv = App::Schierer::HPFan::View::Markdown->new();

  ADJUST {
    $SourceDir = Path::Tiny::path($SourceDir);
    if (!$SourceDir->is_dir()) {
      $self->dev_guard(sprintf(
        '%s requires a directory to import from, not %s.',
        ref($self), $SourceDir
      ));
    }
  }

  # output fields
  field $events = {};

  method events {
    my @out = sort {
           ($a->sortval // 0) <=> ($b->sortval // 0)
        || ($a->date_iso // '') cmp($b->date_iso // '')
        || ($a->id       // '') cmp($b->id       // '')
    } values $events->%*;
    $self->logger->debug(sprintf(
      '%s is returning %s events.', ref($self), scalar @out));
    return \@out;
  }

  method process {
    $self->logger->info('starting processing of Gramps history.');

    my $rule = Path::Iterator::Rule->new();
    $rule->name(qr/\.ya?ml$/);
    $rule->file->nonempty;
    my $iter = $rule->iter(
      $SourceDir,
      {
        follow_symlinks => 0,
        sorted          => 1,
      }
    );

    while (defined(my $file = $iter->())) {
      # work around for UTF8 filenames not importing correctly by default.
      $file = Path::Tiny::path(Encode::decode('utf8', $file));
      $self->logger->debug(sprintf('%s importing %s', ref($self), $file));
      my $basename = $file->basename('.yaml');
      my $name     = $basename;

      my $data   = $file->slurp_utf8;
      my $object = YAML::PP->new(
        schema       => [qw/ + Perl /],
        yaml_version => ['1.2', '1.1'],
      )->load_string($data);
      if ($object) {
        $self->logger->debug(
          sprintf('object is %s', Data::Printer::np($object)));
        unless (exists $object->{events}) {
          $self->dev_guard('%s is missing an events key', $file);
          next;
        }
        foreach my $index (0 .. scalar(@{ $object->{events} })) {
          my $event = $object->{events}->[$index];
          if (scalar keys %$event) {
            $self->process_event($index, $event, $file);
          }
        }
      }
    }
  }

  method process_event ($index, $object, $file) {

    my @types;
    unless (@types = $object->{type} =~
      /(england|gb|ireland|magical|mundane|religious|scotland)/gi) {
      $self->dev_guard(sprintf(
        'unknown category "%s" in %s. Event is %s',
        $object->{type}, $file, Data::Printer::np($object)
      ));
      return;
    }
    $self->logger->debug(sprintf(
      'found %s types in %s, %s',
      scalar(@types), $file, join(', ', @types)
    ));

    unless (exists $object->{blurb}) {
      $self->dev_guard('blurb is required in %s of %s', $index, $file);
      return;
    }

    my $do     = $self->getDate($index, $object, $file);
    my $complete = $do->{complete};
    my $date = $do->{date};
    $self->logger->debug(sprintf('date is of type %s', ref($date) ));
    unless ($date->isa('Date::Calc') && $date->is_valid()){
      $self->dev_guard(sprintf('Invalid Date Object Returned processing %s of %s: ', $index, $file) . Data::Printer::np($date));
    }
    unless($date->year ne "9999"){
      $self->logger->error("Invalid Date Parsed from $index of $file, year 9999 returned");
      return;
    }

    my $sortval = Date_to_Days($date->date());
    $self->logger->debug("sortval is $sortval");

    my $id = sprintf('%s-%s', $file->basename(qr/\.ya?ml$/), $index);
    $events->{$id} = App::Schierer::HPFan::Model::History::Event->new(
      id          => $id,
      blurb       => $object->{blurb},
      raw_date    => \$date,
      date_iso    => sprintf('%d-%02d-%02d', $date->year, $date->month, $date->day),
      sortval     => $sortval,
      event_class => Scalar::Util::blessed($date),
      date_kind   => $complete ? '' : 'estimated',
    );
  }

  method getDate ($index, $object, $file) {
    my $dc;
    my $year;
    my $month = "01";
    my $day   = "01";
    my $complete = 1;
    if (exists $object->{date}) {
      if (($year, $month, $day) =
        $object->{date} =~ /(\d{3,4})-(\d{1,2})-(\d{1,2})/) {
        $year  = sprintf('%04d', $year);
        $month = sprintf('%02d', $month);
        $day   = sprintf('%02d', $day);
        $self->logger->debug("going to give Date::Calc $year $month $day in the year-month-day block");
        $dc    = Date::Calc->new([$year, $month, $day]);
        $dc->accurate_mode(1);
      }
      elsif (($year, $month) = $object->{date} =~ /(\d{3,4})-(\d{1,2})/) {
        $year  = sprintf('%04d', $year);
        $month = sprintf('%02d', $month);
        $day   = "01";
        $self->logger->debug("going to give Date::Calc $year $month $day in the year-month block");
        $dc    = Date::Calc->new([$year, $month, $day]);
        $dc->accurate_mode(1);
        $complete = 0;
      }
      elsif (($year) = $object->{date} =~ /(\d{3,4})/) {
        $year = sprintf('%04d', $year);
        $month = "01";
        $day   = "01";
        $self->logger->debug("going to give Date::Calc $year $month $day in the year alone block");
        $dc   = Date::Calc->new([$year, $month, $day]);
        $dc->accurate_mode(1);
        $complete = 0;
      }
      else {
        my $f = $file->basename(qr/\.ya?ml$/);
        if (($year, $month, $day) = $f =~ /(\d{3,4})-(\d{1,2})-(\d{1,2})/) {
          $year  = sprintf('%04d', $year);
          $month = sprintf('%02d', $month);
          $day   = sprintf('%02d', $day);
          $self->logger->debug("going to give Date::Calc $year $month $day in the year-month-day file block");
          $dc    = Date::Calc->new([$year, $month, $day]);
          $dc->accurate_mode(1);
        }
        elsif (($year, $month) = $f =~ /(\d{3,4})-(\d{1,2})/) {
          $year  = sprintf('%04d', $year);
          $month = sprintf('%02d', $month);
          $day   = "01";
          $self->logger->debug("going to give Date::Calc $year $month $day in the year-month file block");
          $dc    = Date::Calc->new([$year, $month, $day]);
          $dc->accurate_mode(1);
          $complete = 0;
        }
        elsif (($year) = $f =~ /(\d{3,4})/) {
          $year = sprintf('%04d', $year);
          $month = "01";
          $day   = "01";
          $self->logger->debug("going to give Date::Calc $year $month $day in the year alone file block");
          $dc   = Date::Calc->new([$year, $month, $day]);
          $dc->accurate_mode(1);
          $complete = 0;
        }
      }
    }
    if (not defined($dc)) {
      $dc = Date::Calc->new(9999, 12, 01);
      $complete = 0;
    }
    if(not $dc->is_valid){
      $self->logger->logcarp(sprintf('invalid date object created parsing %s of %s: ', $index, $file). Data::Printer::np($dc));
    }
    return {
      date  => $dc,
      complete  => $complete,
    };
  }

}
1;
__END__
method process_birth_event ($e) {
  my @citations;
  my @description;
  if (my $person = $self->_primary_person_for($e)) {

    # handle date
    my @dklparts;
    push @dklparts, $e->date->quality_label
      if (defined $e->date->quality_label && length($e->date->quality_label));
    push @dklparts, $e->date->modifier_label
      if (defined $e->date->modifier_label
      && length($e->date->modifier_label));

    # set up description
    push @description, $e->description if (defined($e->description) && length($e->description));
    my $note_text = $self->_notes_for_event($e);
    push @description, $note_text->@* if(scalar @$note_text);


    # final object
    $events->{ $e->gramps_id } =
      App::Schierer::HPFan::Model::History::Event->new(
      id          => $e->gramps_id,
      blurb       => sprintf('Birth of %s', $person->display_name()),
      date_iso    => (not $e->date->is_range)
      ? $e->date->as_dm_date->printf('%Y-%m-%d')
      : sprintf('%s - %s', $e->date->start, $e->date->end),
      date_kind => scalar @dklparts ? sprintf('(%s)', join(' ', @dklparts),)
      : '',
      description => $mv->format_string(join('\n', @description), {
        asXHTML => 1,
        sizeTemplate  => 'timeline',
      }),
      event_class => 'magical',
      origin      => 'Gramps',
      raw_date => $e->date,
      sortval  => $e->date->sortval,
      type        => 'Birth',
      );
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
    push @dklparts, $e->date->quality_label
      if (defined $e->date->quality_label && length($e->date->quality_label));
    push @dklparts, $e->date->modifier_label
      if (defined $e->date->modifier_label
      && length($e->date->modifier_label));

    # set up description
    push @description, $mv->format_string($e->description, {
      asXHTML => 1,
      sizeTemplate  => 'timeline',
    })
      if (defined($e->description) && length($e->description));

    my $note_text = $self->_notes_for_event($e);
    push @description, $note_text->@* if(scalar @$note_text);



    # final object
    $events->{ $e->gramps_id } =
      App::Schierer::HPFan::Model::History::Event->new(
      id          => $e->gramps_id,
      origin      => 'Gramps',
      type        => 'Death',
      event_class => 'magical',
      blurb       => sprintf('Death of %s', $person->display_name()),
      date_iso    => (not $e->date->is_range)
      ? $e->date->as_dm_date->printf('%Y-%m-%d')
      : sprintf('%s - %s', $e->date->start, $e->date->end),
      date_kind => scalar @dklparts ? sprintf('(%s)', join(' ', @dklparts),)
      : '',
      sortval     => $e->date->sortval,
      raw_date    => $e->date,
      description => join('', @description),
      );
  }
  else {
    $self->logger->warn(sprintf(
      'Death event %s cannot be matched with a person.',
      $e->gramps_id));
  }
}
