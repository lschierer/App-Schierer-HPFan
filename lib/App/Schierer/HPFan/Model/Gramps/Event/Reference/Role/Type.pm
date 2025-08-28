
use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Event::Reference::Role::Type :
  isa(App::Schierer::HPFan::Logger) {
  use Carp ();
  use Readonly;
  use Scalar::Util   qw(blessed looks_like_number);
  use List::AllUtils qw( firstidx );

  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => \&to_string,
    'bool'     => \&_isTrue,
    'fallback' => 1;

  field $_class : param = undef;    # from Gramps JSON
  field $string : param = undef;    # custom label (when value==0)
  field $value  : param = undef;
  field $ROLE_MAP;

  ADJUST {
    # Shared built-in role map; 0 is “custom” (use $string)
    Readonly::Hash my %tmp => (
      1  => 'Primary',
      5  => 'Bride',
      6  => 'Groom',
      11 => 'Father',
      12 => 'Mother',
    );
    $ROLE_MAP = \%tmp;
  }

  method _sortValue {
    my $sortValue;
    if (defined($value)) {
      $self->logger->debug("value is $value");
      if (exists $ROLE_MAP->{$value}) {
        $sortValue =
          firstidx { $_ eq $ROLE_MAP->{$value} } sort values $ROLE_MAP->%*;
      }
      else {
        $self->logger->dev_guard("Missing Sort Map for value $value");
        $sortValue = $value;
      }
    }
    else {
      $self->warn(sprintf('%s has an undefined value', ref($self)));
    }
    $self->logger->debug(sprintf(
      '_sortValue for %s value %s returning %s',
      ref($self),
      defined($value)     ? $value     : 'Undefined',
      defined($sortValue) ? $sortValue : 'Undefined'
    ));
    return $sortValue;
  }

  # ---- Rendering ----
  method to_string {
    # custom string wins for value==0
    if (defined $value && $value == 0 && defined $string && length $string) {
      return $string;
    }

    # built-in mapping
    if (defined $value && exists $ROLE_MAP->{$value}) {
      return $ROLE_MAP->{$value};
    }

    # unknown value? warn in dev, but don’t leak UI details
    if (defined $value) {
      $self->dev_guard(sprintf('Unknown Role::Type value %s!', $value));
      return "$value";    # show number in UI
    }

    # totally unset
    return 'Unknown';
  }

  # ---- Comparisons ----
  method _comparison($other, $swap = 0) {
    my ($a, $b) = $swap ? ($other, $self) : ($self, $other);

    if (blessed($a) && $a->isa(__CLASS__) && blessed($b) && $b->isa(__CLASS__))
    {
      my $cmp = $self->_sortValue <=> $other->_sortValue;
      if ($cmp == 0 && defined($string)) {
        return $string cmp $other->string;
      }
      return $cmp // 1;    # fallback if _sortValue comparison fails
    }

    # Numeric comparison
    if (Scalar::Util::looks_like_number($other)) {
      $self->logger->debug(sprintf(
        '%s comparing as number, %s to %s',
        ref($self), $self->_sortValue, $other
      ));
      return $self->_sortValue <=> $other;
    }

    # String comparison - try _sortValue first, then custom string
    if (my $sr = $self->_sortValue) {
      $self->logger->debug(sprintf(
        '%s comparing _sortValue to string, %s to %s',
        ref($self), $sr, $other
      ));
      return $sr cmp $other;
    }

    if (defined($string)) {
      $self->logger->debug(sprintf(
        '%s comparing custom string, %s to %s',
        ref($self), $string, $other
      ));
      return $string cmp $other;
    }

    return 1;    # fallback
  }

  method _equality($other, $swap = 0) {
    my ($a, $b) = $swap ? ($other, $self) : ($self, $other);

    return 0 unless (defined($a) && defined($b));

    # Same class comparison
    if (blessed($a) && $a->isa(__CLASS__) && blessed($b) && $b->isa(__CLASS__))
    {
      return $a->_comparison($b, $swap) == 0;
    }

    # Numeric comparison
    if (Scalar::Util::looks_like_number($b)) {
      return $a->_sortValue == $b;
    }
    elsif (Scalar::Util::looks_like_number($a)) {
      return $b->_sortValue == $a;
    }

    return "$a" eq "$b";
  }

  method _isTrue {
    return
         defined($self)
      && blessed($self)
      && blessed($self) eq __CLASS__;
  }

}
1;
__END__
