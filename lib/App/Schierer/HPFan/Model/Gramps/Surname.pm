use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Surname:
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'        => \&to_string,
    '.'         => \&to_string,
    'bool'      => sub { $_[0]->_isTrue() },
    'cmp'       => \&_equality,
    'fallback'  => 0;

  field $value      : param : reader //= undef;
  field $prefix     : param : reader = undef;
  field $primary       : param : reader = 0;
  field $derivation : param : reader = "Unknown";
  field $connector  : param : reader = undef;

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  ADJUST {
    unless (defined($value) or (
      defined($XPathContext) and defined($XPathObject)
    )) {
      $self->logger->logcroak('either a value must be provided, or both XPathContext and XPathObject must be.');
    } elsif( not defined($value)){
      $self->_import();
    }

    # Validate derivation types from DTD comment
    my %valid_derivations = map { $_ => 1 } qw(
      Unknown Inherited Given Taken Patronymic Matronymic Feudal
      Pseudonym Patrilineal Matrilineal Occupation Location
    );

    if ($derivation && !$valid_derivations{$derivation}) {
      $self->logger->logcroak( "Invalid derivation type: '$derivation'");
    }
  }

  method display_name {
    my @parts;
    push @parts, $prefix    if $prefix;
    push @parts, $connector if $connector;
    push @parts, $value;
    return join(' ', @parts);
  }

  method _import {
    my $text_content = $XPathObject->textContent();
    unless (defined($text_content) && length($text_content) > 0) {
      # The DtD says this must be present, the export shows
      # that the surname tag can be an empty tag.
      $value = '';
    } else {
      $value = $text_content;
    }

    $prefix = $XPathObject->getAttribute('prefix');
    # Documentation is unclear which is used.
    $primary = $XPathObject->getAttribute('prim') // $XPathObject->getAttribute('primary') // 0;
    $derivation = $XPathObject->getAttribute('derivation');
    $derivation =~ s/^\s+|\s+$//g unless not defined $derivation;
    $connector = $XPathObject->getAttribute('connector');
  }

  method _equality ($other, $swap = 0) {
    return $self->display_name cmp $other->display_name;
  }

  method to_string() {
    my @parts;

    push @parts, $prefix if $prefix;
    push @parts, $value;

    return join(" ", @parts);
  }
}

1;
