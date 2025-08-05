use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
require XML::LibXML;
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

  field $tags   : reader = {};
  field $events : reader = {};
  field $people : reader = {};
  field $families :reader = {};

  ADJUST {
    # Do not assume we are passed a Path::Tiny object;
    $gramps_export = Path::Tiny::path($gramps_export);
    if (!$gramps_export->is_file) {
      $self->logger->logcroak("gramps_export $gramps_export is not a file.");
    }
  }

  method import_from_xml {

    $self->logger->debug("loading from " . $gramps_export->canonpath);
    my $dom = XML::LibXML->load_xml(location => $gramps_export->canonpath);
    my $d = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

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
      if($handle){
        my $id = $xPerson->getAttribute('id');
        my $change = $xPerson->getAttribute('change');
        my $gender = $xc->findvalue('./g:gender', $xPerson) // 'U';
        $gender =~ s/^\s+|\s+$//g;

        my @names;
        foreach my $xName ($xc->findnodes('./g:name', $xPerson)) {
          my $type = $xName->getAttribute('type');
          my $first = $xc->findvalue('./g:first', $xName);
          my $call = $xc->findvalue('./g:call', $xName);
          my $title = $xc->findvalue('./g:title', $xName);
          my $nick = $xc->findvalue('./g:nick', $xName);
          my @surnames;
          foreach my $xSN ($xc->findnodes('./g:surname', $xName)){
            my $derivation = $xSN->getAttribute('derivation') // 'Unknown';
            $derivation =~ s/^\s+|\s+$//g;
            my $value = $xSN->to_literal();
            push @surnames, App::Schierer::HPFan::Model::Gramps::Surname->new(
              value       => $value,
              derivation  => $derivation,
              prim          => scalar @surnames ? 0 : 1,
            );
          }
          my @citationref;
          foreach my $cr ($xc->findnodes('./g:citationref/@hlink', $xName)) {
            push @citationref, $cr->to_literal;
          }
          my $alt = $xName->getAttribute('alt') // 0;
          push @names, App::Schierer::HPFan::Model::Gramps::Name->new(
            type          => $type,
            first         => $first,
            call          => $call,
            surnames      => \@surnames,
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
      if($handle){
        my $type = $xc->findvalue('./g:rel/@type', $xFamily);
        my $father = $xc->findvalue('./g:father/@hlink', $xFamily);
        my $mother = $xc->findvalue('./g:mother/@hlink', $xFamily);
        my $change = $xFamily->getAttribute('change');
        my $id = $xFamily->getAttribute('id');

        my @childref;
        foreach my $cr ($xc->findnodes('./g:childref', $xFamily)) {
          my $hlink = $cr->getAttribute('hlink');
          my @ccr;
          foreach my $chl ($xc->findnodes('./citationref/@hlink')) {
            push @ccr, $chl->to_literal();
          }
          push @childref, {
            hlink         => $hlink,
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
    $self->logger->info(sprintf('imported %s families.', scalar keys %{$families}));
  }

}
1;
__END__
