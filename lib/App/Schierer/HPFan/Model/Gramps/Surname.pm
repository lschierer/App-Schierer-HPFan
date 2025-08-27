use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Surname :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'cmp'      => \&_equality,
    'fallback' => 0;

  field $data : param;
  field $_class = undef;
  field $connector  : reader //= undef;
  field $origintype : reader //= undef;
  field $prefix     : reader //= undef;
  field $primary    : reader //= 0;
  field $surname    : reader //= undef;

  field $derivation : reader //= "Unknown";

  ADJUST {
    $_class     = $data->{_class};
    $connector  = $data->{connector};
    $origintype = $data->{origintype};
    $prefix     = $data->{prefix};
    $primary    = $data->{primary};
    $surname    = $data->{surname};
  }

  method display_name {
    my @parts;
    push @parts, $prefix    if $prefix;
    push @parts, $connector if $connector;
    push @parts, $surname;
    return join(' ', @parts);
  }

  method _equality ($other, $swap = 0) {
    return $self->display_name cmp $other->display_name;
  }

  method to_string() {
    my @parts;
    $self->logger->debug("prefix is $prefix");
    $self->logger->debug("surname is $surname");
    push @parts, $prefix if $prefix;
    push @parts, $surname;

    return join(" ", @parts);
  }
}

1;
