use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Note::Text;
require App::Schierer::HPFan::Model::Gramps::Note::Type;

class App::Schierer::HPFan::Model::Gramps::Note :
  isa(App::Schierer::HPFan::Logger) {
  use List::AllUtils qw( any );
  use Carp;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

    field $data : param;

    field $change     : reader //= undef;
    field $format     : reader //= undef;
    field $gramps_id  : reader //= undef;
    field $handle     : reader //= undef;
    field $private    : reader //= undef;
    field $text       : reader //= undef;
    field $type       : reader //= undef;

    field $tag_list = [];

    method tag_list   { [ $tag_list->@* ] }

  ADJUST {
    $change     = $data->{change};
    $format     = $data->{format};
    $gramps_id  = $data->{gramps_id};
    $handle     = $data->{handle};
    $private    = $data->{private};
    $text       = App::Schierer::HPFan::Model::Gramps::Note::Text->new($data->{text}->%*);
    $type       = App::Schierer::HPFan::Model::Gramps::Note::Type->new($data->{type}->%*);

    foreach my $item ($data->{tag_list}->@*) {
      push @$tag_list, $item;
    }

  }

  method to_string {
    return $self->text;
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{gramps_id} = $self->gramps_id;
    $hr->{text}      = $self->text;
    $hr->{type}      = $self->type;
    return $hr;
  }

  method _comparison ($other, $swap = 0) {
    unless (ref($other) eq 'OBJECT') {
      return -1;
    }
    unless ($other->isa('App::Schierer::HPFan::Model::Gramps::Note')) {
      return -1;
    }
    my $tcmp = $self->type <=> $other->type;
    if ($tcmp == 0) {
      return $self->text cmp $other->text;
    }
    return $tcmp;

  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method TO_JSON {
    my $json = $self->json_data;
  }

}
1;
__END__
