use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require YAML::PP;
require Scalar::Util;
require Sereal::Encoder;
require Sereal::Decoder;
require Date::Manip;

package App::Schierer::HPFan::Controller::History {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';

  sub register($self, $app, $config) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(__PACKAGE__ . " Register method start");

    my $timeline;

    if ($app->config('gramps_initialized') && !$timeline) {
      $timeline = $self->_build_timeline($app->gramps);
      foreach my $event (@$timeline) {
        if ($event->{description} && length($event->{description})) {
          $event->{description} =
            $app->render_markdown_snippet($event->{description});
        }
        if ($event->{source} && length($event->{source})) {
          $event->{source} = $app->render_markdown_snippet($event->{source});
        }
      }
    }
    else {
      $app->plugins->on(
        'gramps_initialized' => sub($c, $gramps) {
          # Build the unified timeline
          $timeline = $self->_build_timeline($gramps);
          foreach my $event (@$timeline) {
            if ($event->{description} && length($event->{description})) {
              $event->{description} =
                $app->render_markdown_snippet($event->{description});
            }
            if ($event->{source} && length($event->{source})) {
              $event->{source} =
                $app->render_markdown_snippet($event->{source});
            }
          }
        }
      );
    }

    $app->routes->get('/Harrypedia/History')->to(
      controller => 'History',
      action     => 'timeline_handler',
    );

    $app->add_navigation_item({
      title => 'Timeline of Relevent Events',
      path  => '/Harrypedia/History',
      order => 1,
    });

    # Store in helper for access
    $app->helper(history_timeline => sub { return $timeline });

  }

  sub timeline_handler ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);

    my $timeline = $c->history_timeline;

    $c->stash(
      timeline => $timeline,
      title    => 'Timeline of Relevent Events',
      template => 'history/timeline',
      layout   => 'default'
    );

    return $c->render;
  }

  sub _build_timeline($self, $gramps) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    my $history_dir =
      Mojo::File::Share::dist_dir('App::Schierer::HPFan')->child('history');

    my @all_events;

    # Find all YAML files in the history directory
    my $rule = Path::Iterator::Rule->new;
    my $iter = $rule->file->name(qr/\.yaml$/)->iter($history_dir);

    while (my $file_path = $iter->()) {
      $logger->debug("Processing history file: $file_path");

      my $events = $self->_process_history_file($file_path);
      push @all_events, @$events if $events;
    }

    my $ge = $self->_process_gramps_events($gramps);
    $logger->debug(sprintf(
      'retrieved %s events from gramps', $ge ? scalar @$ge : '0'));

    push @all_events, @$ge if $ge;

    # Sort events by date
    @all_events = sort {
      my $date_cmp = $a->{date}->cmp($b->{date});

      # If dates are different, use date comparison
      if ($date_cmp != 0) {
        return $date_cmp;
      }

      # Dates are the same, now handle qualifiers
      my $a_type = $a->{date_type} // '';
      my $b_type = $b->{date_type} // '';

      # Both have 'before' - sort by blurb
      if ($a_type eq 'before' && $b_type eq 'before') {
        return $a->{blurb} cmp $b->{blurb};
      }

      # Both have 'after' - sort by blurb
      if ($a_type eq 'after' && $b_type eq 'after') {
        return $a->{blurb} cmp $b->{blurb};
      }

      # One has 'before', other doesn't - 'before' comes first
      if ($a_type eq 'before' && $b_type ne 'before') {
        return -1;
      }
      if ($b_type eq 'before' && $a_type ne 'before') {
        return 1;
      }

      # One has 'after', other doesn't - 'after' comes last
      if ($a_type eq 'after' && $b_type ne 'after') {
        return 1;
      }
      if ($b_type eq 'after' && $a_type ne 'after') {
        return -1;
      }

      # Neither has qualifiers, or both have same non-before/after qualifier
      return $a->{blurb} cmp $b->{blurb};
    } @all_events;

    $logger->info(
      sprintf("Built timeline with %d total events", scalar @all_events));

    return \@all_events;
  }

  sub _determine_gramps_date($self, $ged) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug("determining timeline date from gramps date $ged");
    my $err;
    my $eventDate = {
      date_type => '',
      date      => Date::Manip::Date->new(),
    };
    $eventDate->{date}->config("language",         "English");
    $eventDate->{date}->config("Use_POSIX_Printf", 1);
    $eventDate->{date}->config("SetDate",          "zone,UTC");

    if ($ged =~ /between/) {
      if ($ged =~ /([-0-9]+)\s+and\s+([-0-9]+)/) {
        $logger->debug("this is a 'between' date.");
        $eventDate->{date}->parse($2);
      }
      $eventDate->{date_type} = 'before';
    }
    elsif ($ged =~ /([-0-9]+)/) {
      $eventDate->{date}->parse($1);
    }
    if ($err) {
      $logger->warn(sprintf(
        'returning date "now" for date %s  because of error: %s',
        $ged, $err
      ));
      $eventDate->{date_type} = 'invalid';
      return $eventDate;
    }
    if ($ged =~ /before/i) {
      $logger->debug('this is a "before" date.');
      $eventDate->{date_type} = 'before';
    }
    $eventDate->{date}->set('h',  0);
    $eventDate->{date}->set('mn', 0);
    $eventDate->{date}->set('s',  0);
    return $eventDate;
  }

  sub _find_gramps_event_description($self, $gramps, $event) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    my @description;
    if (ref($event->note_refs) ne 'ARRAY') {
      $logger->error('note_refs not an array!! ' . ref($event->note_refs));
      return '';
    }
    foreach my $nr ($event->note_refs->@*) {
      my $note = $gramps->notes->{$nr};
      if ($note) {
        push @description, $note->text;
      }

    }

    if ($event->type =~ /birth/i) {
      my @people;
      foreach my $p ($gramps->people_by_event->{ $event->handle }->@*) {
        push @people, $p;
      }
      if (scalar @people) {
        foreach my $nr ($people[0]->note_refs->@*) {
          my $note = $gramps->notes->{$nr};
          if ($note) {
            push @description, $note->text;
          }
        }
      }
    }
    if (scalar @description) {
      return join '\n', @description;
    }
    # markdown_render_snippet requires at least one character of text
    return ' ';
  }

  sub _process_gramps_events($self, $gramps) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    my @grampsEvents;
    foreach my $event (values $gramps->events->%*) {
      if ($event->type !~ /(Hogwarts Sorting|Education)/) {
        next unless ($event->date);
        my $now       = Date::Manip::Date->new();
        my $eventDate = $self->_determine_gramps_date(
          $gramps->date_parser->format_date($event->date));
        if ($eventDate->{date_type} eq 'invalid') {
          $logger->debug("skipping event with invalid date_type");
          next;
        }

        my @people;
        foreach my $p ($gramps->people_by_event->{ $event->handle }->@*) {
          push @people, $p;
        }
        if ($event->type =~ /(Engagement|Marriage)/i) {
          next unless scalar(@people);
        }
        if ($event->type =~ /(Birth|Death)/i) {
          next unless scalar(@people) == 1;
        }

        $logger->debug(sprintf(
          'found eligible event type "%s" date "%s", people: %s.',
          $event->type,
          $eventDate->{date}->printf('%Y-%m-%d'),
          join(', ', map { $_->display_name } @people)
        ));
        my $blurb;
        if ($event->type =~ /Elected/i) {
          next unless scalar(@people) >= 1;
          $blurb =
            sprintf('%s elected Minister of Magic', $people[0]->display_name);
        }
        elsif ($event->type =~ /property/i) {
          next unless scalar(@people) >= 1;
          $blurb = sprintf('Property Awarded to %s', $people[0]->display_name);
        }
        elsif ($event->type =~ /government/i) {
          next unless length($event->description);
          $blurb = $event->description;
        }
        elsif (scalar @people) {
          $blurb = sprintf('%s of %s',
            $event->type, join(', ', map { $_->display_name } @people));
        }
        elsif (length($event->description)) {
          $blurb = $event->description;
        }
        else {
          $logger->warn(
            'no blurb known for event with handle ' . $event->handle);
          next;
        }

        $logger->debug("blurb is '$blurb'");

        my $ge = {
          date        => $eventDate->{date},
          date_type   => $eventDate->{date_type},
          type        => 'magical',
          blurb       => $blurb,
          description => $self->_find_gramps_event_description($gramps, $event),
          source      => $self->_build_event_sources($gramps, $event),
        };
        push @grampsEvents, $ge;
      }
    }
    return \@grampsEvents;
  }

  sub _build_event_sources($self, $gramps, $event) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    my @citations;

    # Get citations for this event
    foreach my $citation_ref ($event->citation_refs->@*) {
      my $citation = $gramps->citations->{$citation_ref};
      next unless $citation;

      my $source = $gramps->sources->{ $citation->sourceref };
      next unless $source;

      my $mla_citation =
        $self->_format_mla_citation($gramps, $source, $citation);
      push @citations, "- $mla_citation" if $mla_citation;
    }

    return @citations ? join("\n", @citations) : '';
  }

  sub _format_mla_citation($self, $gramps, $source, $citation) {
    my @parts;

    # Author (if available)
    if (my $author = $source->sauthor) {
      # Handle "Last, First" format for MLA
      if ($author =~ /^([^,]+),\s*(.+)$/) {
        push @parts, "$1, $2.";
      }
      else {
        push @parts, "$author.";
      }
    }

    # Title (required)
    if (my $title = $source->stitle) {
      # Italicize book/work titles in markdown
      push @parts, "*$title*.";
    }

    # Publication info (publisher, date, etc.)
    if (my $pubinfo = $source->spubinfo) {
      push @parts, $pubinfo;
    }

    # Repository information (if available)
    foreach my $repo_ref ($source->repo_refs->@*) {
      my $repository = $gramps->repositories->{ $repo_ref->handle };
      next unless $repository;

      if (my $repo_name = $repository->rname) {
        push @parts, $repo_name;

        # Add medium if specified
        if (my $medium = $repo_ref->medium) {
          push @parts, $medium;
        }

        # Add URL if available
        if (my $url = $repository->url) {
          push @parts, $url;
        }
      }
    }

    # Page reference from citation
    if (my $page = $citation->page) {
      # Add page reference
      if (@parts) {
        $parts[-1] =~ s/\.$//;    # Remove trailing period from last part
        push @parts, "p. $page.";
      }
      else {
        push @parts, "p. $page.";
      }
    }

    # Citation date (when the source was accessed/cited)
    if (my $cite_date = $citation->date) {
      push @parts, "Accessed " . $cite_date;
    }

    return join(' ', @parts);
  }

  sub _process_history_file($self, $file_path) {
    my $logger   = Log::Log4perl->get_logger(__PACKAGE__);
    my $file     = Mojo::File->new($file_path);
    my $filename = $file->basename('.yaml');

    # Parse the YAML
    my $yaml = YAML::PP->new;
    my $data;

    eval { $data = $yaml->load_file($file_path); };

    if ($@) {
      $logger->error("Failed to parse YAML file $file_path: $@");
      return [];
    }

    unless ($data && $data->{events} && ref($data->{events}) eq 'ARRAY') {
      $logger->warn("No events array found in $file_path");
      return [];
    }

    my @events;

    foreach my $event (@{ $data->{events} }) {
      # Add file-based date info if event doesn't have its own date

      my $eventDate;
      $eventDate = $event->{date} if exists $event->{date};
      unless (exists $event->{date}) {
        if ($filename !~ /\d{2}th/ and $filename =~ /^\d+$/) {
          $eventDate = sprintf('%04d', $filename);
        }
        else {
          $eventDate = $filename;
        }
      }
      $logger->debug("eventDate is $eventDate");

      my $dm = new Date::Manip::Date;
      $dm->config("language",         "English");
      $dm->config("Use_POSIX_Printf", 1);
      $dm->config("SetDate",          "zone,UTC");

      my $err;
      if ($eventDate =~ /(\d{1,2})th/) {
        # Century only - very truncated
        my $century = 100 * ($1 - 1);
        $logger->debug("Century String detected: $century");
        $err = $dm->parse($century);
      }
      elsif ($eventDate =~ /(\d+)-(\d+)-(\d+)/
        or $eventDate =~ /(\d+)-(\d+)/
        or $eventDate =~ /^(\d+)/) {
        $eventDate =~ s/^(\d{3})$/0$1/;
        $eventDate =~ s/^(\d{3})-(.+)$/0$1-$2/;

        $err = $dm->parse($eventDate);
      }
      else {
        $logger->error(sprintf(
          'unknown date format for event in %s!! %s',
          $filename, Data::Printer::np($event)
        ));
        $err = $dm->parse('%Y-%m-%d', '9999-12-31');
      }

      # Check if parsing was successful
      if ($err) {
        $logger->error("Date Parsing Failed: $err");
        $dm->parse('9999-12-31');    # Fallback
      }
      $dm->set('h',  0);
      $dm->set('mn', 0);
      $dm->set('s',  0);

      $event->{date} = $dm;
      $logger->debug(sprintf(
        'event date is now type "%s" and formats as "%s"',
        ref $event->{date},
        $event->{date}->printf('%Y-%m-%d') // 'UNKNOWN'
      ));

      # Add source file for debugging
      $event->{_source_file} = $filename;

      push @events, $event;
    }

    return \@events;
  }

}
1;
__END__
