use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type;
require Scalar::Util;

class App::Schierer::HPFan::Model::Gramps::Person::Child::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    'cmp'      => sub { $_[0]->_comparison },
    'eq'       => sub { $_[0]->_equality },
    '""'       => sub { $_[0]->to_string },
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $data : param;

  field $rel     : reader //= undef;
  field $frel    : reader : writer //= undef;
  field $mrel    : reader : writer //= undef;
  field $private : reader //= undef;

  field $citation_list = [];
  field $note_list     = [];

  ADJUST {
    $rel = $data->{rel};
    $frel =
      App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type->new(
      $data->{frel}->%*);
    $mrel =
      App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type->new(
      $data->{mrel}->%*);
    $private = $data->{private};

    foreach my $item ($data->{citation_list}->@*) {
      push @$citation_list, $item;
    }

    foreach my $item ($data->{note_list}->@*) {
      push @$note_list, $item;
    }

  }

  method father_rel {$frel}
  method mother_rel {$mrel}

  method citation_list { [$citation_list->@*] }
  method note_list     { [$note_list->@*] }

  method to_hash {
    my $r = $self->SUPER::to_hash;
    $r->{rel}        = $rel;
    $r->{father_rel} = $frel;
    $r->{mother_rel} = $mrel;
    return $r;
  }

}
1;
__END__
