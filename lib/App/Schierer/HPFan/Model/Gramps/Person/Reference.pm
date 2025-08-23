use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type;
require Scalar::Util;

class App::Schierer::HPFan::Model::Gramps::Person::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;
  use overload
    'cmp'      => sub { $_[0]->_comparison },
    'eq'       => sub { $_[0]->_equality },
    '""'       => sub { $_[0]->to_string },
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $rel  : param : reader //= undef;
  field $frel : param //= undef;
  field $mrel : param //= undef;

  field $father_rel : reader : writer = undef;
  field $mother_rel : reader : writer = undef;

  ADJUST {
    unless (defined $father_rel) {
      if (defined $frel && Scalar::Util::reftype($frel) eq 'HASH') {
        $self->set_father_rel(
          App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type
            ->new(
            $frel->%*
            )
        );
      }
    }

    unless (defined($mrel)) {
      if (defined $mrel && Scalar::Util::reftype($mrel) eq 'HASH') {
        $self->set_mother_ref(
          App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type
            ->new(
            $mrel->%*
            )
        );
      }
    }

  }

  method to_hash {
    my $r = $self->SUPER::to_hash;
    $r->{rel}        = $rel;
    $r->{father_rel} = $father_rel;
    $r->{mother_rel} = $mother_rel;
    return $r;
  }

}
1;
__END__
