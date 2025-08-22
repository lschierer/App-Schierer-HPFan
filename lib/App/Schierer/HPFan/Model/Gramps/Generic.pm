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

  field $handle         : param : reader = undef;

  field $dbh : reader : param : writer //= undef;
  field $ALLOWED_FIELD_NAMES : reader = {
    handle          => 1,
    change          => 1,
    attribute_list  => 1,
    private         => 1,
    json_data       => 1,
  };

  ADJUST {

    if (exists $self->ALLOWED_FIELD_NAMES->{'handle'} &&
        $self->ALLOWED_FIELD_NAMES->{'handle'}) {
      #unless (defined($handle)) {
      #  $self->logger->logcroak('handle must be defined.');
      #}
    }

  }

  method private {
    if(exists $self->ALLOWED_FIELD_NAMES->{'private'}){
      if($self->ALLOWED_FIELD_NAMES->{'private'}){
        return $self->_get_field('private');
      }
    }
    return 0;
  }

  method json_data {
    if(exists $self->ALLOWED_FIELD_NAMES->{'json_data'}){
      if($self->ALLOWED_FIELD_NAMES->{'json_data'}){
        return $self->_get_field('json_data');
      }
    }
    return {};
  }

  method change {
    if(exists $self->ALLOWED_FIELD_NAMES->{'change'}){
      if($self->ALLOWED_FIELD_NAMES->{'change'}){
        return $self->_get_field('change');
      }
    }
    return time;
  }

  method note_refs {
    my $items = [];
    if(exists $self->ALLOWED_FIELD_NAMES->{'json_data'}){
      my $hash = JSON::PP->new->decode($self->json_data);
      foreach my $item ($hash->{'note_list'}->@*) {
        push @$items,
          App::Schierer::HPFan::Model::Gramps::Note::Reference->new($item->%*);
      }
    }
    return [ $items->@* ];
  }

  method citation_refs {
    my $items = [];
    if(exists $self->ALLOWED_FIELD_NAMES->{'json_data'}){
      my $hash = JSON::PP->new->decode($self->json_data);
      foreach my $item ($hash->{'citation_list'}->@*) {
        push @$items,
          App::Schierer::HPFan::Model::Gramps::Reference->new($item->%*);
      }
    }
    return [ $items->@* ];
  }

  method tag_refs {
    my $items = [];
    if(exists $self->ALLOWED_FIELD_NAMES->{'json_data'}){
      my $hash = JSON::PP->new->decode($self->json_data);
      foreach my $item ($hash->{'tag_list'}->@*) {
        push @$items,
          App::Schierer::HPFan::Model::Gramps::Reference->new($item->%*);
      }
    }
  }

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
      change        => $self->change,
      note_refs     => [$self->note_refs->@*],
      citation_refs => [$self->citation_refs->@*],
      tag_refs      => [$self->tag_refs->@*],
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
