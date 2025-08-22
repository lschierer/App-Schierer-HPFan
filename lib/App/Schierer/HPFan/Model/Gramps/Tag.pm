use v5.42;
use utf8::all;
use experimental qw(class);
require JSON::PP;
require Data::Printer;

class App::Schierer::HPFan::Model::Gramps::Tag :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;

  ADJUST {
    my @desired = qw(
    handle  name  color   priority
    change  json_data );

    my @names;
    push @names, @desired;
    push @names, keys $self->ALLOWED_FIELD_NAMES->%*;
    foreach my $tn (@names) {
      if(any {$_ eq $tn} @desired){
        $self->ALLOWED_FIELD_NAMES->{$tn} = 1;
      } else {
        $self->ALLOWED_FIELD_NAMES->{$tn} = undef;
      }
    }
  }

  method name      { $self->_get_field('name') }
  method color     { $self->_get_field('color') }
  method priority  { $self->_get_field('priority') }


  method parse_json_data {
    my $hash = JSON::PP->new->decode($self->json_data);
    $self->logger->debug(sprintf(
      'hash for tag "%s" is: %s',
      $self->handle, Data::Printer::np($hash),
    ));
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{name}     = $self->name;
    $hr->{color}    = $self->color;
    $hr->{priority} = $self->priority;
    return $hr;
  }

}

1;
