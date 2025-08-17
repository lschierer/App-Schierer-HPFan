use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::DateHelper;
require App::Schierer::HPFan::Model::Gramps::Surname;

class App::Schierer::HPFan::Model::Gramps::Name :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    '.'        => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'fallback' => 0;

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  field $priv  : reader //= 0;
  field $type  : reader //= undef;
  field $value : reader //= undef;

  field $citation_refs : param //= [];
  field $note_refs     : param //= [];

  method citation_refs() { [$citation_refs->@*] }
  method note_refs()     { [$note_refs->@*] }

  ADJUST {
    $self->import();
  }

  method _import {
    $priv  = $XPathObject->getAttribute('priv') // 0;
    $type  = $XPathObject->getAttribute('type');
    $value = $XPathObject->getAttribute('value');

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

  }

}
1;
__END__
