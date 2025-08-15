use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;

class App::Schierer::HPFan::Model::Gramps::Style :
  isa(App::Schierer::HPFan::Logger){

  field $name : reader : param //= undef;
  field $value : reader : param //= undef;
  field $range : param //= [];

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  ADJUST {
    if (
      not(defined($name)
        or (defined($XPathContext) and defined($XPathObject)))
    ) {
      $self->logger->logcroak(
        'Either name, or both XPathContext and XPathObject must be provided.'
      );
    }
    elsif (not defined($name)) {
      $self->_import();
    }
  }

  method range()     { [ $range-@* ] }

  method _import {
    $name = $XPathObject->getAttribute('handle');
    $self->logger->logcroak("name not discoverable in $XPathObject")
      unless defined $name;

    $value = $XPathObject->getAttribute('value');
    foreach my $r ($XPathContext->findnodes('./g:range', $XPathObject)){
      my $start = $r->getAttribute('start');
      my $end = $r->getAttribute('end') ;
      push @$range, {
        start   => $start,
        end     => $end,
      };
    }
  }
}
1;
__END__
