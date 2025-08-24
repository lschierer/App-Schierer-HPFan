use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Object::Reference;
require App::Schierer::HPFan::Model::Gramps::Source::Reference;
require App::Schierer::HPFan::Model::CustomDate;

class App::Schierer::HPFan::Model::Gramps::Citation :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use List::AllUtils qw( any );
  use Carp;

  ADJUST {
    my @desired = qw(
      handle  gramps_id   page  confidence  source_handle
      change  private   json_data );
    my @names;
    push @names, @desired;
    push @names, keys $self->ALLOWED_FIELD_NAMES->%*;
    foreach my $tn (@names) {
      if (any { $_ eq $tn } @desired) {
        $self->ALLOWED_FIELD_NAMES->{$tn} = 1;
      }
      else {
        $self->ALLOWED_FIELD_NAMES->{$tn} = undef;
      }
    }
  }

  method gramps_id  { $self->_get_field('gramps_id') }
  method page       { $self->_get_field('page') }
  method confidence { $self->_get_field('confidence') }

  method source_handle {
    return App::Schierer::HPFan::Model::Gramps::Source::Reference->new(
      ref => $self->_get_field('source_handle'));
  }

  method parse_json_data {
    #trust DBH::SQLite to have already handle UTF8.
    my $hash = JSON::PP->new->decode($self->json_data);
    if (reftype($hash) eq 'HASH') {
      $self->logger->info("got hash " . Data::Printer::np($hash));

    }
  }

}
1;
__END__
