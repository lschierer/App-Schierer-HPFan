use v5.42.0;
use utf8::all;
require Log::Log4perl;
use namespace::autoclean;

package App::Schierer::HPFan::Schema::Gramps::Result::Person {
  use Moo;    # Use Moo for robust, lightweight object system.
  use namespace::autoclean;
  use JSON::PP;
  use DBIx::Class::Core;
  use DBIx::Class::EncodedColumn;
  use Carp;

  # Inherit from DBIx::Class::Core
  extends 'DBIx::Class::Core';

  # Use EncodedColumn for JSON processing
  with 'DBIx::Class::EncodedColumn';

  # Set up the table and columns declaratively.
  __PACKAGE__->table('person');
  __PACKAGE__->add_columns(
    'handle'     => { data_type => 'varchar', is_nullable => 0, size => 50 },
    'given_name' => { data_type => 'text',    is_nullable => 1 },
    'surname'    => { data_type => 'text',    is_nullable => 1 },
    'gramps_id'  => { data_type => 'text',    is_nullable => 1 },
    'gender' => { data_type => 'integer', is_nullable => 1, is_numeric => 1 },
    'death_ref_index' =>
      { data_type => 'integer', is_nullable => 1, is_numeric => 1 },
    'birth_ref_index' =>
      { data_type => 'integer', is_nullable => 1, is_numeric => 1 },
    'change'  => { data_type => 'integer', is_nullable => 1, is_numeric => 1 },
    'private' => { data_type => 'integer', is_nullable => 1, is_numeric => 1 },
    'json_data' => { data_type => 'text', is_nullable => 1 },
    # The virtual column for the JSON data.
    'data' => {
      accessor   => 'data',
      is_virtual => 1,
      encoder => sub { state $json = JSON::PP->new->utf8; $json->encode(@_) },
      decoder => sub { state $json = JSON::PP->new->utf8; $json->decode(@_) },
      value_column => 'json_data',
    }
  );
  __PACKAGE__->set_primary_key('handle');

}
1;
__END__
