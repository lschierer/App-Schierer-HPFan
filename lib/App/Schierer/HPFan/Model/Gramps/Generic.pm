use v5.42;
use utf8::all;
use experimental qw(class);
use File::FindLib 'lib';
require Data::Printer;
require Date::Manip;

require XML::LibXML;
require JSON::PP;

class App::Schierer::HPFan::Model::Gramps::Generic :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '<=>' => \&_comparison,
    '=='  => \&_equality,
    '!='  => \&_inequality,
    '""'  => \&as_string;

  field $handle        :param :reader = undef;
  field $change        :param = undef;
  field $note_refs     = [];
  field $citation_refs = [];
  field $tag_refs      = [];

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  field $dbh :reader :param //= undef;

  ADJUST {
   unless(defined($handle)) {
    unless(defined($XPathContext) and defined($XPathObject)){
      $self->logger->logcroak('either handle, or XPathContext and XPathObject must be defined.');
    }
    $self->_import();
   }
  }

  method change()        { $change }
  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }
  method tag_refs()      { [@$tag_refs] }

  method _import {
    $handle = $XPathObject->getAttribute('handle');
    $change = $XPathObject->getAttribute('change');
    $self->logger->logcroak("handle not discoverable in $XPathObject")
      unless defined $handle;
    $self->logger->logcroak("Timestamp not discoverable in $XPathObject")
      unless defined $change;

    foreach my $ref (
      $self->XPathContext->findnodes('./g:noteref', $self->XPathObject)) {
      push @$note_refs,
        App::Schierer::HPFan::Model::Gramps::Note::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }

    foreach my $ref (
      $self->XPathContext->findnodes('./g:citationref', $self->XPathObject)) {
      push @$citation_refs,
        App::Schierer::HPFan::Model::Gramps::Citation::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }

    foreach my $ref ($self->XPathContext->findnodes('./g:tagref')) {
      push @$tag_refs,
        App::Schierer::HPFan::Model::Gramps::Tag::Reference->new(
        XPathContext => $self->XPathContext,
        XPathObject  => $ref,
        );
    }
  }

  method _equality ($other, $swap = 0) {
    return $handle eq $other->handle;
  }

  method _inequality ($other, $swap = 0) {
    return $handle ne $other->handle;
  }

  method _comparison ($other, $swap = 0) {
    return $handle cmp $other->handle;
  }

  method to_hash {
    return {
      handle        => $handle,
      change        => $change,
      note_refs     => [$note_refs->@*],
      citation_refs => [$citation_refs->@*],
      tag_refs      => [$tag_refs->@*],
    };
  }

  method as_string {
    my $json =
      JSON::PP->new->utf8->pretty->canonical(1)
      ->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}
