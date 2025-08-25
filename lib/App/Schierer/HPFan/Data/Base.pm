use v5.42.0;
use experimental qw(class);
use utf8::all;
require Log::Log4perl;
require JSON::PP;
use namespace::autoclean;

package App::Schierer::HPFan::Data::Base {
  use Mojo::Base -base, -strict, -signatures;

  our $logger = Log::Log4perl->get_logger(__PACKAGE);

  has 'result';

  sub new ($class, $result_obj) {
    my $self = $class->SUPER::new;
    $self->result($result_obj);
    return $self;
  }

  sub data ($self) {
    my $json_text = $self->result->json_data;
    return JSON::PP->new->utf8->decode($json_text);
  }

  sub set_data ($self, $hashref) {
    my $json_text = JSON::PP->new->utf8->encode($hashref);
    $self->result->json_data($json_text);
    $self->result->update;
  }
}
