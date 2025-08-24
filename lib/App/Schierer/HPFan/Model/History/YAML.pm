use v5.42.0;
use experimental qw(class);
use utf8::all;

require App::Schierer::HPFan::Model::History::Event;
require YAML::PP;
require Path::Tiny;
require Path::Iterator::Rule;
require App::Schierer::HPFan::Model::CustomDate;

class App::Schierer::HPFan::Model::History::YAML :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
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

    my $date = $self->getDate($index, $object, $file);

    my $sortval = $date->sortval;
    $self->logger->debug("sortval is $sortval");

    my $id = sprintf('%s-%s', $file->basename(qr/\.ya?ml$/), $index);
    $events->{$id} = App::Schierer::HPFan::Model::History::Event->new(
      id       => $id,
      blurb    => $object->{blurb},
      raw_date => \$date,
      date_iso =>
        sprintf('%d-%02d-%02d', $date->year, $date->month, $date->day),
      sortval     => $sortval,
      event_class => join(' ', @types),
      date_kind   => $date->complete ? '' : 'estimated',
    );
  }

  method getDate ($index, $object, $file) {
    my $dc;
    if (exists $object->{date}) {
      $dc =
        App::Schierer::HPFan::Model::CustomDate->new(text => $object->{date});
    }
    else {
      my $f = $file->basename(qr/\.ya?ml$/);
      $dc = App::Schierer::HPFan::Model::CustomDate->new(text => $f);
    }
    if (not defined($dc)) {
      $self->dev_guard(sprintf(
        'could not get date for %s of %s.', $index, $file));
      return undef;
    }
    return $dc;

  }

}
1;
__END__
