package App::Schierer::HPFan::Role::Gramps;
  use Mojo::Base -role, -signatures;
  use v5.42.0;
  use utf8::all;
  use experimental qw(class);
  require App::Schierer::HPFan::Model::Gramps;
  require Mojo::Promise;

  has 'gramps_export' => sub { return Mojo::Home->new->detect->child('share/data/gramps'); };
  has 'gramps_db'     => sub { return Mojo::Home->new->detect->child('share/grampsdb/sqlite.db'); };

  my $g;
  my $init_promise;
  my $ready = 0;

  sub gramps ($self) {
    $g //= App::Schierer::HPFan::Model::Gramps->new(
      gramps_export => $self->gramps_export,
      gramps_db     => $self->gramps_db,
    );
    return $g;
  }

  sub initialize ($self) {
    $init_promise //= Mojo::Promise->timer(0.1 => sub {
      $self->logger->info("⚙️  Running gramps import...");
      $self->gramps->execute_import();
    })->then(sub {
      Mojo::Promise->timer(0.1);
    })->then(sub {
      $self->logger->info("⚙️  Building gramps indexes...");
      $self->gramps->build_indexes();
    })->then(sub {
      $self->logger->info("✅ gramps import completed.");
      $ready = 1;
    });

    return $init_promise;
  }

  sub ensure_ready ($self) {
    return if $ready;
    $self->initialize()->wait;  # blocks until promise resolves
  }

  sub person_house ($self, $person) {
    $self->ensure_ready;

    my %by_handle =
      %{ $self->gramps->tags };    # handle => Tag (assumes ->name or similar)

    for my $th (@{ $person->tag_list // [] }) {
      my $tag  = $by_handle{$th} or next;
      my $name = $tag->name // '';
      $name =~ s/^\s+|\s+$//g;

      # exact house names
      return $name
        if $name =~ /^(?:Gryffindor|Hufflepuff|Ravenclaw|Slytherin)$/;

      # "House: Gryffindor" etc.
      if ($name =~
        /^House:\s*(Gryffindor|Hufflepuff|Ravenclaw|Slytherin)\b/i) {
        return ucfirst lc $1;
      }
    }

    return 'Unknown House';
  }

  sub person_blood_status ($self, $person) {
    $self->ensure_ready;

    my %by_handle =
      %{ $self->gramps->tags };    # handle => Tag (assumes ->name or similar)

    for my $th (@{ $person->tag_list // [] }) {
      my $tag  = $by_handle{$th} or next;
      my $name = $tag->name // '';
      $name =~ s/^\s+|\s+$//g;

      # exact house names
      return $name
        if $name =~
        /^(?:pure-blood|half-blood|1st gen magical|hag|non-magical)$/;
    }

    return 'Unknown Status';
  }

  sub person_economic_status ($self, $person) {
    $self->ensure_ready;

    my %by_handle =
      %{ $self->gramps->tags };    # handle => Tag (assumes ->name or similar)

    for my $th (@{ $person->tag_list // [] }) {
      my $tag  = $by_handle{$th} or next;
      my $name = $tag->name // '';
      $name =~ s/^\s+|\s+$//g;

      # exact house names
      return $name
        if $name =~ /^(?:Lower Class|Upper Class|Middle Class)$/;
    }

    return 'Unknown';
  }

1;
__END__
