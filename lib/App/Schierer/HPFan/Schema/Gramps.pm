use v5.42.0;
use utf8::all;

package App::Schierer::HPFan::Schema {
  use Moo;
  use DBIx::Class::Schema;
  use Carp;

# Inherit from DBIx::Class::Schema
  extends 'DBIx::Class::Schema';

# Use MooseX::NonMoose if you want to avoid potential conflicts
# with inherited methods, though it's less critical here.
  use MooseX::NonMoose;

# Automatically load the Result classes
  __PACKAGE__->load_namespaces;

}

1;
__END__
