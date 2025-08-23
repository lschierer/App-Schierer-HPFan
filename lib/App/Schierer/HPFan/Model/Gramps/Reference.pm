use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require Scalar::Util;
require App::Schierer::HPFan::Model::Gramps::Note::Reference;

class App::Schierer::HPFan::Model::Gramps::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use Readonly;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,              # string equality
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $_class         : param //= undef;
  field $citation_list  : param //= [];
  field $note_list      : param //= [];
  field $ref            : param : reader //= undef;
  field $role           : param : reader : writer = undef;
  field $attribute_list : param : reader = [];
  field $private        : param //= undef;

  ADJUST {
    my @names;
    push @names, keys $self->ALLOWED_FIELD_NAMES->%*;
    foreach my $tn (@names) {
      $self->ALLOWED_FIELD_NAMES->{$tn} = undef;
    }

    if (scalar @{$attribute_list}) {
      $self->dev_guard(
        sprintf('%s encountered a populated attribute_list', CORE::ref($self)));
    }
  }

  method private { $self->private ? 1 : 0 }

  method citation_list { [$citation_list->@*] }
  method note_list     { [$note_list->@*] }

  method _comparison ($other, $swap = 0) {
    return $self->ref cmp $other->ref;
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method to_hash {
    return {} if $self->private;
    my $r = { ref => $ref };
    $r->{'citation_list'} = $citation_list if (scalar @$citation_list);
    $r->{'note_list'}     = $citation_list if (scalar @$note_list);
    $r->{'role'}          = $role          if (defined $role);
    return $r;
  }

  method to_string {
    my $json =
      JSON::PP->new->utf8->pretty->canonical(1)
      ->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}
1;
__END__
