use v5.42.0;
use experimental qw(class);
use utf8::all;

class App::Schierer::HPFan::Model::History::Gramps::footnote
  : isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( first );
  use Carp;

  field $event      : param;
  field $people     : param = [];
  field $gramps     : param;

  field $result = [];

  method footnote {

    $self->citations_for_event();

    return $result;
  }

  method citations_for_event {
    $self->logger->debug(sprintf('there are %s citations for event %s',
    scalar @{ $event->citation_list }, $event->gramps_id));

    foreach my $cr ( $event->citation_list->@*){
      my $cite = $gramps->citations->{$cr};
      my $isWebCitation = 0;
      my $sh = $cite->source_handle;
      my $source = $gramps->sources->{$sh};
      my $repos = [];

      foreach my $rh ($source->reporef_list->@*) {
        my $rht = $rh->media_type;
        # the only repositories with valuable info are the electronic ones.
        if("$rht" eq 'Electronic'){
          $isWebCitation = 1;
          push @$repos, $gramps->repositories->{$rh->ref} if defined($gramps->repositories->{$rh->ref});
        }
      }

      unless($source){
        $self->logger->warn(sprintf('citation %s points at non-existant source %s.',
        $cite->gramps_id, $sh));
        next;
      }

      my $title = ( defined($source->title) && length($source->title)) ? $source->title
        : scalar(@$repos) ? first { defined($_->name) && length($_->name) } @$repos : 'Unknown';

      $title = sprintf('<dt class="%s">%s</dd>',
        'spectrum-Heading spectrum-Heading--sizeXS spectrum-Heading-emphasized',
        $title
      );

      my $author = sprintf(
        '<dd class="%s">%s</dd>',
        'spectrum-Detail spectrum-Detail--serif spectrum-Detail--sizeS',
        $source->author // 'Unknown'
        );

      my $page = defined($cite->page) && length($cite->page) ? sprintf('<dd class="%s">Page: %s</dd>',
      'spectrum-Body spectrum-Body--serif spectrum-Detail--sizeS',
      $cite->page) : '' ;

      my $date = defined($cite->date) && $cite->date->year != 9999 ? sprintf('<dd class="%s">%s</dd>',
      'spectrum-Body spectrum-Body--serif spectrum-Body--sizeS',
      $cite->date) : '' ;
      push @$result, join '', ($title, $author, $date, $page, );

    }
  }


}
1;
__END__
