use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Style;

class App::Schierer::HPFan::Model::Gramps::Note :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;

  ADJUST {
    my @desired = qw(
      handle  gramps_id   format
      change  private     json_data );

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

  method styles { my $hash = JSON::PP->new->decode($self->json_data); }

  method gramps_id { $self->_get_field('gramps_id') }
  method format     { $self->_get_field('format') }

  method parse_json_data {
    my $hash = JSON::PP->new->decode($self->json_data);
    $self->logger->debug(sprintf(
      'hash for tag "%s" is: %s',
      $self->handle, Data::Printer::np($hash),
    ));

  }

}
1;
__END__
