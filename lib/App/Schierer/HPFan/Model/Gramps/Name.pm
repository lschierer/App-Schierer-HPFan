use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::DateHelper ;
require App::Schierer::HPFan::Model::Gramps::Surname;

class App::Schierer::HPFan::Model::Gramps::Name :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    '.'        => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'fallback' => 0;

  field $alt        : reader : param = 0;
  field $type       : reader : param = "Birth Name";
  field $priv       : reader : param = 0;
  field $sort       : reader : param = undef;
  field $display    : param = undef;
  field $first      : reader : param = undef;
  field $call       : reader : param = undef;
  field $nick       : reader : param = undef;
  field $familynick : reader : param = undef;
  field $group      : reader : param = undef;
  field $surnames   : param = [];
  field $suffix     : reader : param = undef;
  field $title      : reader : param = undef;
  field $date       : reader : param =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $note_refs     : param = [];
  field $citation_refs : param = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  ADJUST {
    # Validate that surnames is an array of Surname objects
    if (!$XPathObject && !$XPathContext) {
        # This is fine - creating an empty name object
        $self->logger->debug("Creating name object from provided parameters.");
    }
    elsif ($XPathObject && $XPathContext) {
        # Import from XML
        $self->_import();
    }
    elsif ($XPathObject || $XPathContext) {
        # Only one provided - that's an error
        $self->logger->logcroak("Must provide both XPathObject and XPathContext for import, or neither");
    }

    if (@$surnames) {
      for my $surname (@$surnames) {
        $self->logger->logcroak( "surnames must be Surname objects")
          unless ref($surname) eq
          'App::Schierer::HPFan::Model::Gramps::Surname';
      }
    }
  }

  method surnames() { [@$surnames] }

  method note_refs()     { [@$note_refs] }
  method citation_refs() { [@$citation_refs] }

  method primary_surname() {
    # Return the primary surname (prim=1) or first surname
    for my $surname (@$surnames) {
      return $surname if $surname->primary;
    }
    return @$surnames ? $surnames->[0] : undef;
  }

  method display {
    return $display if $display;
    my @parts;
    push @parts, $first  if $first;
    push @parts, $call   if ($call and not $first);
    push @parts, "$nick" if ($nick and not $first);
    if (not scalar @parts) {
      push @parts, 'Unknown';
    }
    return join(' ', @parts);
  }

  method _import {
    $alt = $XPathObject->getAttribute('alt');
    $priv = $XPathObject->getAttribute('priv') // 0;
    $type = $XPathObject->getAttribute('type');
    $sort = $XPathObject->getAttribute('sort');
    $display = $XPathObject->getAttribute('display');
    $first = $XPathContext->findvalue('./g:first', $XPathObject);
    $call = $XPathContext->findvalue('./g:call', $XPathObject);
    $nick = $XPathContext->findvalue('./g:nick', $XPathObject);
    $familynick = $XPathContext->findvalue('./g:familynick', $XPathObject);
    $group = $XPathContext->findvalue('./g:group', $XPathObject);
    $suffix = $XPathContext->findvalue('./g:suffix', $XPathObject);
    $title = $XPathContext->findvalue('./g:title', $XPathObject);
    $date = $dh->import_gramps_date($XPathObject, $XPathContext);

    foreach my $sno ($XPathContext->findnodes('./g:surname', $XPathObject)){
      push @$surnames, App::Schierer::HPFan::Model::Gramps::Surname->new(
        XPathContext  => $XPathContext,
        XPathObject   => $XPathObject,
      );
    }

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

  method to_string {
    my @parts;

    push @parts, $title if $title;
    push @parts, $first if $first;

    if (my $primary_surname = $self->primary_surname) {
      push @parts, $primary_surname->to_string;
    }

    push @parts, $suffix if $suffix;

    my $name = join(" ", @parts) || "Unknown";

    if ($nick) {
      $name .= " \"$nick\"";
    }

    return $name;
  }
}

1;
