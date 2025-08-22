use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Url;

class App::Schierer::HPFan::Model::Gramps::Repository :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;

  field $gramps_id  : param = undef;
  field $name       : param = undef;
  field $json_data  : param = undef;

  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw(
      gramps_id   handle  change
      name        private json_data) };

  method gramps_id { $self->_get_field('gramps_id') }
  method name      { $self->_get_field('name') }
  method json_data { $self->_get_field('json_data') }
  method change    { $self->_get_field('change') }
  method private   { $self->_get_field('private') }

  method parse_json_data {
    my $hash = JSON::PP->new->decode($self->json_data);
    $self->logger->debug(sprintf(
      'hash for tag "%s" is: %s',
      $self->handle, Data::Printer::np($hash),
    ));

    if (exists $hash->{'attribute_list'} &&  scalar @{ $hash->{'attribute_list'} }) {
      $self->logger->dev_guard(
        sprintf('%s found a non-empty attribute_list', ref($self)));
    }

    foreach my $item ($hash->{'note_list'}->@*) {
      push @{ $self->note_refs }, $item,;
    }

    foreach my $item ($hash->{'tag_list'}->@*) {
      push @{ $self->tag_refs }, $item;
    }
  }

  method type {
    my $hash = JSON::PP->new->decode($self->json_data);
    my $rt = App::Schierer::HPFan::Model::Gramps::Repository::Type->new($hash->{'type'}->%*);
    return $rt;
  }

}
1;
__END__
