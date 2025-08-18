use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Person::ChildReferenceType;
require Scalar::Util;

class App::Schierer::HPFan::Model::Gramps::Person::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  field $rel  : param : reader //= undef;
  field $frel : param //= undef;
  field $mrel : param //= undef;

  field $father_ref : writer = undef;
  field $mother_ref : writer = undef;

  ADJUST {
    unless (defined $father_ref) {
      if (defined $frel && Scalar::Util::reftype($frel) eq 'HASH') {
        $self->set_father_ref(
          App::Schierer::HPFan::Model::Gramps::Person::ChildReferenceType->new(
            $frel->%*
          )
        );
      }
    }

    unless (defined($mrel)) {
      if (defined $mrel && Scalar::Util::reftype($mrel) eq 'HASH') {
        $self->set_mother_ref(
          App::Schierer::HPFan::Model::Gramps::Person::ChildReferenceType->new(
            $mrel->%*
          )
        );
      }
    }

  }

}
1;
__END__
