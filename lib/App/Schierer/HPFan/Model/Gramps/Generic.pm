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

  field $handle : param : reader = undef;
  field $change : param = undef;
  field $note_refs     = [];
  field $citation_refs = [];
  field $tag_refs      = [];

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  field $dbh : reader : param : writer //= undef;
  field $ALLOWED_FIELD_NAMES : reader = {};

  ADJUST {
    unless (defined($handle)) {
      unless (defined($XPathContext) and defined($XPathObject)) {
        $self->logger->logcroak(
          'either handle, or XPathContext and XPathObject must be defined.');
      }
      $self->_import();
    }
  }

  method change()        {$change}
  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }
  method tag_refs()      { [@$tag_refs] }

  field $table_names : reader = {
    citation     => 1,
    gender_stats => 1,
    name_group   => 1,
    place        => 1,
    source       => 1,
    event        => 1,
    media        => 1,
    note         => 1,
    reference    => 1,
    tag          => 1,
    family       => 1,
    metadata     => 1,
    person       => 1,
    repository   => 1,
  };

  method class_to_table_name {
    my @parts = split('::', ref($self));
    my $base  = pop @parts;

    if ($base) {
      if (exists $table_names->{ lc($base) }) {
        return lc($base);
      }
    }
    return 'metadata';
  }

  method _get_field ($field_name, $table_name = undef) {

    # guard the table name
    unless (defined $table_name) {
      $table_name = $self->class_to_table_name;
    }
    unless (exists $table_names->{$table_name}) {
      $table_name = 'metadata';
    }

    if (exists $self->ALLOWED_FIELD_NAMES->{$field_name}) {
      unless ($self->dbh) {
        $self->dev_guard('_get_field called without defined dbh!!!');
        return undef;
      }

      my $table_name = my $sql =
        "SELECT $field_name FROM $table_name WHERE handle = ?";
      my $result = $self->dbh->selectrow_hashref($sql, undef, $self->handle);
      return $result ? $result->{$field_name} : undef;
    }
    $self->dev_guard("_get_field requested for forbidden field $field_name");
    return undef;
  }

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
