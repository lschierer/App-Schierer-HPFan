use v5.42;
use utf8::all;
use experimental qw(class);
use Readonly;

class App::Schierer::HPFan::Model::Gramps::EventType :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

  field $_class : param //= undef;
  field $string : param : reader //= undef;
  field $value  : param : reader //= undef;
  field $value_to_string;
  field $value_to_sort_order;

  ADJUST {
    Readonly::Hash my %tmp => {
      0  => $string,
      1  => 'Marriage',
      6  => 'Engagement',
      7  => 'Divorce',
      12 => 'Birth',
      13 => 'Death',
      26 => 'Education',
      27 => 'Elected',
      31 => 'Graduation',
      37 => 'Occupation',
      40 => 'Property',
      43 => 'Retirement',
    };
    $value_to_string = \%tmp;
  }

  ADJUST {
    Readonly::Hash my %tmp => {
      12 => 1,
      26 => 2,
      31 => 3,
      6  => 4,
      1  => 5,
      7  => 6,
      37 => 20,
      27 => 27,
      40 => 30,
      43 => 80,
      0  => 99,
      13 => 99,
    };
    $value_to_sort_order = \%tmp;
  }
  state %SEEN;
  method _sortValue {
    my $sortValue = 999;
    if(defined($value)) {
      if(exists $value_to_sort_order->{$value}){
        $sortValue = $value_to_sort_order->{$value};
      } else {
        $self->logger->dev_guard("Missing Sort Map for value $value") unless( $SEEN{$value}++);
        $sortValue = $value;
      }
    }
    return $sortValue;
  }

  method _comparison($other, $swap = 0) {
      # Same class comparison
      if (ref($other) && $other->isa(__CLASS__)) {
          my $cmp = $self->_sortValue <=> $other->_sortValue;
          if ($cmp == 0 && defined($string)) {
              return $string cmp $other->string;
          }
          return $cmp // 1;  # fallback if _sortValue comparison fails
      }

      # Numeric comparison
      if (Scalar::Util::looks_like_number($other)) {
          $self->logger->debug(sprintf('%s comparing as number, %s to %s',
              ref($self), $self->_sortValue, $other));
          return $self->_sortValue <=> $other;
      }

      # String comparison - try _sortValue first, then custom string
      if (my $sr = $self->_sortValue) {
          $self->logger->debug(sprintf('%s comparing _sortValue to string, %s to %s',
              ref($self), $sr, $other));
          return $sr cmp $other;
      }

      if (defined($string)) {
          $self->logger->debug(sprintf('%s comparing custom string, %s to %s',
              ref($self), $string, $other));
          return $string cmp $other;
      }

      return 1;  # fallback
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
      if (defined($value) && exists $value_to_string->{$value}) {
        my $sr = $value_to_string->{$value};
          return $sr eq $other;
      }

      if (defined($string)) {
          return $string eq $other;
      }

      return 0;
  }

  # Return a stable “label”: prefer custom string; else builtin; else BuiltIn(n)
  method label {
    return $string if defined($string) && length $string;    # custom
    return $value_to_string->{$value}
      if defined $value && exists $value_to_string->{$value};
    if (defined($value)) {
      $self->dev_guard(
        "Value is defined: $value, but no mapping exists for it!!!");
      return $value;
    }
    return 'Unknown';
  }

  method to_string { $self->label }

}
1;
__END__
