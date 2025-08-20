
use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Family::Relationship :
  isa(App::Schierer::HPFan::Logger) {
  use Carp ();
  use Readonly;
  use Scalar::Util   qw(blessed looks_like_number);
  use List::AllUtils qw( firstidx );
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,              # string equality
    '""'       => \&to_string,              # used for concat too
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1;

  field $_class : param = undef;            # from Gramps JSON
  field $string : param = undef;            # custom label (when value==0)
  field $value  : param = undef;            # numeric enum

  # Shared built-in role map; 0 is “custom” (use $string)
  Readonly::Hash my %ROLE_MAP => (
    0 => 'Married',
    1 => 'Unmarried',
    2 => 'Civil Union',
    3 => 'Unknown',
  );

  # ---- Rendering ----
  method to_string {
    # custom string wins for value==0
    if (defined $value && $value == 0 && defined $string && length $string) {
      return $string;
    }

    # built-in mapping
    if (defined $value && exists $ROLE_MAP{$value}) {
      return $ROLE_MAP{$value};
    }

    # unknown value? warn in dev, but don’t leak UI details
    if (defined $value) {
      $self->dev_guard(sprintf('Unknown RoleType value %s!', $value));
      return "$value";    # show number in UI
    }

    # totally unset
    return 'Unknown';
  }

  # ---- Comparisons ----

  method _sortValue {
    my $sortValue;
    if (defined($value)) {
      if (exists $ROLE_MAP{$value}) {
        $sortValue = firstidx { $_ eq $ROLE_MAP{$value} } sort values %ROLE_MAP;
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

  method _comparison($other, $swap = 0) {
    # Same class comparison
    if (ref($other) && $other->isa(__CLASS__)) {
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
    return 0 unless defined($other);

    # Same class comparison
    if (ref($other) && $other->isa(__CLASS__)) {
      return $self->_comparison($other, $swap) == 0;
    }

    # Numeric comparison
    if (Scalar::Util::looks_like_number($other)) {
      return $self->_sortValue == $other;
    }

    # String comparison
    if (defined($value) && exists $ROLE_MAP{$value}) {
      my $sr = $ROLE_MAP{$value};
      return $sr eq $other;
    }

    if (defined($string)) {
      return $string eq $other;
    }

    return 0;
  }

}
1;
__END__
