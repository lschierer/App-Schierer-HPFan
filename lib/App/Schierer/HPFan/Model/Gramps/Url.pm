use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require URI;

class App::Schierer::HPFan::Model::Gramps::Url :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '<=>' => \&_comparison,
    '=='  => \&_equality,
    '!='  => \&_inequality,
    '""'  => \&as_string;

  field $priv : reader : param //= undef;
  field $type : reader : param //= undef;
  field $href : param //= undef;
  field $description : reader : param //= undef;

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  method href {
    return URI->new($href);
  }
  ADJUST {
    if (not(
      defined($href) or (defined($XPathContext) and defined($XPathObject)))) {
      $self->logger->logcroak(
        'Either href, or both XPathContext and XPathObject must be provided.');
    }
    elsif (not defined($href)) {
      $self->_import();
    }
  }

  method _import {
    $href = $XPathObject->getAttribute('href');
    $self->logger->logcroak('href is required') unless defined $href;

    $type        = $XPathObject->getAttribute('type');
    $priv        = $XPathObject->getAttribute('priv');
    $description = $XPathObject->getAttribute('description');

  }

  method as_string {
    if ($priv) {
      return '';
    }
    if (not(defined($type) and defined($description))) {
      return "<$href>";
    }
    else {
      my @parts;
      push @parts, $type;
      push @parts, "<$href>";
      push @parts, $description;
      return join '; ', @parts;
    }
  }
}
1;
