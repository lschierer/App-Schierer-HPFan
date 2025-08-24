use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require JSON::PP;
require Data::Printer;
require App::Schierer::HPFan::Model::Gramps::Repository::Reference;

class App::Schierer::HPFan::Model::Gramps::Source :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use List::AllUtils qw( any );

  #table fields
  field $gramps_id = undef;
  field $title     = undef;
  field $author    = undef;
  field $pubinfo   = undef;
  field $abbrev    = undef;

  ADJUST {
    my @desired = qw(
      gramps_id   handle  change
      title       author  abbrev
      pubinfo   json_data private  );
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

  method gramps_id { $self->_get_field('gramps_id') }
  method title     { $self->_get_field('title') }
  method author    { $self->_get_field('author') }
  method pubinfo   { $self->_get_field('pubinfo') }
  method abbrev    { $self->_get_field('abbrev') }

  method parse_json_data {
    my $hash = JSON::PP->new->decode($self->json_data);
    $self->logger->debug(sprintf(
      'hash for tag "%s" is: %s',
      $self->handle, Data::Printer::np($hash),
    ));

    if (scalar @{ $hash->{'attribute_list'} }) {
      $self->logger->dev_guard(
        sprintf('%s found a non-empty attribute_list', ref($self)));
    }

    if (scalar @{ $hash->{'media_list'} }) {
      $self->logger->dev_guard(
        sprintf('%s found a non-empty attribute_list', ref($self)));
    }
  }

  method repo_refs {
    my $repo_refs = [];
    my $hash      = JSON::PP->new->decode($self->json_data);
    foreach my $item ($hash->{'reporef_list'}->@*) {
      push @$repo_refs,
        App::Schierer::HPFan::Model::Gramps::Repository::Reference->new(
        $item->%*);
    }
    return [$repo_refs->@*];
  }
}
1;
__END__
