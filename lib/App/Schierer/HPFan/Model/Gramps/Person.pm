use v5.42;
require Log::Log4perl;
use utf8::all;

package App::Schierer::HPFan::Model::Gramps::Person {
  use Mojo::Base -base, -signatures;
  use JSON::PP;
  use Carp;

  our $logger = Log::Log4perl->get_logger(__PACKAGE__);

  has 'result';    # Will hold the DBIx::Class result object

  sub new($class, $result_obj) {
    return $class->SUPER::new(result => $result_obj);
  }

  sub data($self) {
    return $self->result->data;
  }

  sub set_data($self, $hashref) {
    $self->result->data($hashref);
  }

  sub save($self) {
    $self->result->update;
  }

}
1;
__END__
