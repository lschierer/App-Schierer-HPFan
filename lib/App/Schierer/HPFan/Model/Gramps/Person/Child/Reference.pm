use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type;
require Scalar::Util;

class App::Schierer::HPFan::Model::Gramps::Person::Child::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Scalar::Util qw(blessed);
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => sub { $_[0]->to_string },
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

  field $data : param;

  field $ref     : reader //= undef;
  field $frel    : reader //= undef;
  field $mrel    : reader //= undef;
  field $private : reader //= undef;

  field $citation_list = [];
  field $note_list     = [];

  ADJUST {
    $ref = $data->{ref};

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

  method citation_list { [$citation_list->@*] }
  method note_list     { [$note_list->@*] }

  method to_hash {
    $self->logger->debug("::Person::Child::Reference to_hash");
    my $r = {};
    $r->{ref}  = $ref;
    $r->{frel} = $frel;
    $r->{mrel} = $mrel;
    return $r;
  }

  method _comparison ($other, $swap = 0) {
    $self->logger->debug("::Person::Child::Reference _comparison");
    my ($a, $b) = $swap ? ($other, $self) : ($self, $other);

    if (blessed($a) && $a->isa(__CLASS__) && blessed($b) && $b->isa(__CLASS__))
    {
      # First compare by the referenced handle
      my $rc = ($a->ref // '') cmp($b->ref // '');
      return $rc if $rc;

      # Then by father/mother relationship types
      my $fc = ($a->frel // '') cmp($b->frel // '');
      return $fc if $fc;

      return ($a->mrel // '') cmp($b->mrel // '');
    }

    # Fallback string compare if other isn’t same class
    return "$a" cmp "$b";
  }

  method _equality ($other, $swap = 0) {
    $self->logger->debug("::Person::Child::Reference _equality");
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

}
1;
__END__
