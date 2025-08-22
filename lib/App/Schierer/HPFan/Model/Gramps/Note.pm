use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Note::Text;
require App::Schierer::HPFan::Model::Gramps::Note::Type;

class App::Schierer::HPFan::Model::Gramps::Note :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

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

  method text {
    my $hash = JSON::PP->new->decode($self->json_data);
    my $tn = $hash->{'text'} if exists $hash->{'text'};
    return App::Schierer::HPFan::Model::Gramps::Note::Text->new(
      $tn->%*
    ) if defined ($tn);
    return undef;
  }

  method type {
    my $hash = JSON::PP->new->decode($self->json_data);
    if(exists $hash->{'type'}){
      return App::Schierer::HPFan::Model::Gramps::Note::Type->new( $hash->{'type'}->%* );
    }
    return undef;
  }

  method to_string {
    return $self->text;
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{gramps_id}  = $self->gramps_id;
    $hr->{text}       = $self->text;
    $hr->{type}       = $self->type;
    return $hr;
  }

  method _comparison ($other, $swap = 0) {
    unless (ref($other) eq 'OBJECT') {
      return -1;
    }
    unless ($other->isa('App::Schierer::HPFan::Model::Gramps::Note')) {
      return -1;
    }
    my $tcmp = $self->type <=> $other->type;
    if($tcmp == 0){
      return $self->text cmp $other->text;
    }
    return $tcmp;

  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method TO_JSON {
    my $json = $self->json_data;
  }

}
1;
__END__
