use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Event::Type;
require App::Schierer::HPFan::Model::CustomDate;

class App::Schierer::HPFan::Model::Gramps::Event :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use List::AllUtils qw( any );
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

  field $data : param;

  field $change       : reader //= undef;
  field $date         : reader //= undef;
  field $description  : reader //= undef;
  field $gramps_id    : reader //= undef;
  field $handle       : reader //= undef;
  field $place        : reader //= undef;
  field $private      : reader //= 0;
  field $type         : reader //= undef;

  field $place_ref : reader = undef;

  field $attribute_list = [];
  field $citation_list  = [];
  field $note_list      = [];
  field $tag_list       = [];

  method attribute_list   { [ $attribute_list->@* ] }
  method citation_list    { [ $citation_list->@* ] }
  method note_list        { [ $note_list->@* ] }
  method tag_list()       { [ $tag_list->@* ] }

  ADJUST {
    $change       = $data->{change};
    $date         = App::Schierer::HPFan::Model::CustomDate->new( text => $data->{date});
    $description  = $data->{description};
    $gramps_id    = $data->{gramps_id};
    $handle       = $data->{handle};
    $place        = $data->{place};
    $private      = $data->{private};
    $type         = App::Schierer::HPFan::Model::Gramps::Event::Type->new($data->{type}->%*);

    foreach my $item ($data->{attribute_list}->@*) {
      push @$attribute_list, $item;
    }

    foreach my $item ($data->{citation_list}->@*) {
      push @$citation_list, $item;
    }

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }
  }

  method to_string {
    my @parts;

    push @parts, $self->type;

    if (my $date_str = $self->date->to_string) {
      push @parts, "($date_str)";
    }

    push @parts, $self->description if length($self->description);

    my $desc = @parts ? join(" ", @parts) : "Unknown event";
    return sprintf("Event[%s]: %s", $self->handle, $desc);
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{id}          = $self->gramps_id;
    $hr->{type}        = $self->type;
    $hr->{date}        = $self->date;
    $hr->{place_ref}   = $place_ref;
    $hr->{description} = $self->description;
    $hr->{attribute_list}   = [$attribute_list->@*];
    $hr->{citation_list}    = [$citation_list->@*];
    $hr->{note_list}        = [$note_list->@*];
    $hr->{tag_list}         = [$tag_list->@*];
    return $hr;
  }

  method _comparison ($other, $swap = 0) {
    unless (ref($other) eq 'OBJECT') {
      return -1;
    }
    unless ($other->isa('App::Schierer::HPFan::Model::Gramps::Event')) {
      return -1;
    }
    my $dateEquality = 0;
    my $d            = $self->date;
    my $oDate        = $other->date;
    if ($d && $oDate) {
      $dateEquality = $d cmp $oDate;
    }
    elsif ($d) {
      return -1;
    }
    elsif ($oDate) {
      return 1;
    }

    if (not $dateEquality) {
      return $self->to_string cmp $other->to_string;
    }
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method TO_JSON {
    my $json =
      JSON::PP->new->utf8->pretty->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}

1;
