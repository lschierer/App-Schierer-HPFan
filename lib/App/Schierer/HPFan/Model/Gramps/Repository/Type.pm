use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::Repository::Type :
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
  field $value  : param = undef;

  field $ENUM;

  ADJUST {
    # Shared built-in role map; 0 is “custom” (use $string)
    Readonly::Hash my %tmp => (
      6  => 'Web Site',
      8  => 'Collection',
      99 => $string // 'Custom',
    );
    $ENUM = \%tmp;
  }

  # ---- Rendering ----
  method to_string {

    # built-in mapping
    if (defined $value && exists $ENUM->{$value}) {
      return $ENUM->{$value};
    }

    # unknown value? warn in dev, but don’t leak UI details
    if (defined $value) {
      $self->dev_guard(sprintf('Unknown ENUM value %s!', $value));
      return "$value";    # show number in UI
    }

    # totally unset
    return 'Unknown';
  }

  # ---- Comparisons ----
  method _comparison($other, $swap = 0) {
    # Same class comparison

    my $va =
        defined($value)
      ? exists $ENUM->{$value}
        ? $ENUM->{$value}
        : $value
      : 'Unknown';

    if (ref($other) && $other->isa(__CLASS__)) {
      my $vb =
          defined($other->value)
        ? exists $ENUM->{ $other->value }
          ? $ENUM->{ $other->value }
          : $other->value
        : 'Unknown';
      return "$va" cmp "$vb";
    }

    # Numeric comparison
    if (Scalar::Util::looks_like_number($other)) {
      $self->logger->debug(sprintf(
        '%s comparing as number, %s to %s', $va, $other));
      return "$va" cmp "$other";
    }

    # String comparison - try _sortValue first, then custom string
    if (my $sr = $self->_sortValue) {
      $self->logger->debug(sprintf(
        '%s comparing as string, %s to %s', $va, $other));
      return "$va" cmp $other;
    }

# I'm not handling where $other is some sort of object but *Not* an instance of this class.
# I currently have no custom strings in my data, leave handling that as a TODO for when I do
# because when I do, I'll know the ENUM value for 'Other'

    return 1;    # fallback
  }

  method _equality($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

}
1;
__END__
SELECT DISTINCT
    json_extract(value, '$.type.value') as value,
    gramps_id
FROM repository WHERE json_extract(type, '$.type') IS NOT NULL;
     json_each(s.json_data, '$.type_list') as type
WHERE json_extract(type.value, '$.media_type.value') IS NOT NULL
GROUP BY json_extract(type.value, '$.media_type.value')
ORDER BY media_type_value;
