
use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Family::Relationship :
  isa(App::Schierer::HPFan::Logger) {
  use Carp ();
  use Readonly;
  use Scalar::Util qw(blessed looks_like_number);
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
    0   => 'Married',
    1   => 'Unmarried',
    2   => 'Civil Union',
    3   => 'Unknown',
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
  method _comparison ($other, $swap = 0) {
    # Coerce $other into something comparable
    my ($ovalue, $ostring);

    if (blessed($other) && $other->isa(__CLASS__)) {
      ($ovalue, $ostring) = ($other->value, $other->string);
    }
    else {
      # Numeric if it looks numeric; else treat as custom string
      if (defined $other && looks_like_number($other)) {
        $ovalue  = $other +0;
        $ostring = undef;
      }
      else {
        $ovalue  = 0;                                    # custom bucket
        $ostring = defined($other) ? "$other" : undef;
      }
    }

    # If both are built-ins (nonzero), numeric compare
    if ((($value // 0) != 0) && (($ovalue // 0) != 0)) {
      return ($value // 0) <=> ($ovalue // 0);
    }

    # If both are custom (value==0), compare strings case-insensitively
    if ((($value // 0) == 0) && (($ovalue // 0) == 0)) {
      my $a = defined($string)  ? lc $string  : '';
      my $b = defined($ostring) ? lc $ostring : '';
      return $a cmp $b;
    }

    # Custom (0) sorts before built-in by default
    return (($value // 0) == 0) ? -1 : 1;
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

}
1;
__END__
