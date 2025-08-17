use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Citation::Reference;
require App::Schierer::HPFan::Model::Gramps::Note::Reference;

class App::Schierer::HPFan::Model::Gramps::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,              # string equality
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $_class         : param = undef;
  field $attribute_list : param = [];
  field $citation_list  : param = [];
  field $note_list      : param = [];
  field $private        : param = 0;
  field $ref            : param = undef;
  field $role           : param : reader : writer = undef;

  # there are a number of optional fields that are common to some,
  # but not all, reference types. Many of these are *almost* ubiquitous
  # and even more are totally unique to references.
  # I am representing these by adding the
  # *_attribute_optional for a subclass to indicate this *may* be present and
  # *_attribute_required for a subclass to indicate this *must* be present
  # these two fields are only used internally, but need to be *settable* by
  # child classes.

  ADJUST {
    if (scalar(@$attribute_list)) {
      $self->dev_guard(
        sprintf('%s found a non-empty attribute_list.', ref($self)));
    }

    if (scalar @{$citation_list}) {
      my @temp;
      foreach my $item ($citation_list->@*) {
        $self->logger->debug("pushing $item as citation ref");
        push @temp, $item;
      }
      $self->set_citationref(\@temp);
    }

    if (scalar @{$note_list}) {
      my @temp;
      foreach my $item ($note_list->@*) {
        $self->logger->debug("pushing $item as note ref");
        push @temp, $item;
      }
      $self->set_noteref(\@temp);
    }

  }

  field $attribute_attribute_optional : writer = 0;
  field $attribute_attribute_required : writer = 0;
  field $attribute = [];

  field $citationref_attribute_optional : writer = 0;
  field $citationref_attribute_required : writer = 0;
  field $citationref                    : writer = [];

  field $noteref_attribute_optional : writer = 0;
  field $noteref_attribute_required : writer = 0;
  field $noteref                    : writer = [];

  method _comparison ($other, $swap = 0) {
    return $ref cmp $other->ref;
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method to_hash {
    return { ref => $ref };
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
