use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Note::Reference;
require App::Schierer::HPFan::Model::Gramps::Place::Reference;
require App::Schierer::HPFan::Model::Gramps::Object::Reference;
require App::Schierer::HPFan::Model::Gramps::Event::Type;

class App::Schierer::HPFan::Model::Gramps::Event :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use App::Schierer::HPFan::Model::Gramps::DateHelper;
  use List::AllUtils qw( any );
  use overload
    'cmp'      => \&_comparison,
    'eq'       => \&_equality,
    '""'       => \&to_string,
    'bool'     => sub { $_[0]->_isTrue },
    'fallback' => 1,
    'nomethod' => sub { croak "No overload method for $_[3]" };

  field $place_ref : reader = undef;    # handle reference to place
  field $cause     : reader = undef;
  field $attributes = [];               # unused, for future growth
  field $obj_refs   = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();

  ADJUST {
    my @desired = qw( gramps_id description place change  private json_data);
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

  method description {
    my $d = $self->_get_field('description');
    $d =~ s/^\s+|\s+$//g;
    return $d;
  }
  method place   { $self->_get_field('place') }
  method change  { $self->_get_field('change') }
  method private { $self->_get_field('private') // 0; }

  method parse_json_data {
    my $rj = $self->json_data();
    $self->logger->debug(sprintf('event sees json_data %s', $rj));
    my $hash = JSON::PP->new->decode($rj);
    if (reftype($hash) eq 'HASH') {
      $self->logger->info("got event hash " . Data::Printer::np($hash));

    }
    else {
      $self->logger->error(
        sprintf('parsed event json resulted in %s', reftype($hash)));
    }
    return {};
  }

  method event_refs {
    my $items = [];
    if (exists $self->ALLOWED_FIELD_NAMES->{'json_data'}) {
      my $hash = JSON::PP->new->decode($self->json_data);
      foreach my $item ($hash->{'event_ref_list'}->@*) {
        push @$items,
          App::Schierer::HPFan::Model::Gramps::Event::Reference->new($item->%*);
      }
    }
    return [$items->@*];
  }

  method date {
    my $hash = JSON::PP->new->decode($self->json_data);
    my $d    = $dh->parse($hash->{'date'});
    $self->logger->debug("found date " . Data::Printer::np($d));
    return $d;
  }

  method type {
    my $hash = JSON::PP->new->decode($self->json_data);
    my $type =
      App::Schierer::HPFan::Model::Gramps::Event::Type->new($hash->{type}->%*);
    return $type;
  }

  method attributes() { [@$attributes] }
  method obj_refs()   { [@$obj_refs] }

  method to_string {
    my @parts;

    push @parts, $self->type;

    if (my $date_str = $self->date->to_string) {
      push @parts, "($date_str)";
    }

    push @parts, $self->description if length($self->description);

    my $desc = @parts ? join(" ", @parts) : "Unknown event";
    return sprintf("Event[%s]: %s", $self->handle, $desc);
  }

  method to_hash {
    my $hr = $self->SUPER::to_hash;
    $hr->{id}          = $self->gramps_id;
    $hr->{type}        = $self->type;
    $hr->{date}        = $self->date->to_string;
    $hr->{place_ref}   = $place_ref;
    $hr->{cause}       = $cause;
    $hr->{description} = $self->description;
    $hr->{attributes}  = [$attributes->@*];
    $hr->{obj_refs}    = [$obj_refs->@*];
    return $hr;
  }

  method _comparison ($other, $swap = 0) {
    unless (ref($other) eq 'OBJECT') {
      return -1;
    }
    unless ($other->isa('App::Schierer::HPFan::Model::Gramps::Event')) {
      return -1;
    }
    my $dateEquality = 0;
    my $d            = $self->date;
    my $oDate        = $other->date;
    if ($d && $oDate) {
      $dateEquality = $d cmp $oDate;
    }
    elsif ($d) {
      return -1;
    }
    elsif ($oDate) {
      return 1;
    }

    if (not $dateEquality) {
      return $self->to_string cmp $other->to_string;
    }
  }

  method _equality ($other, $swap = 0) {
    return $self->_comparison($other, $swap) == 0 ? 1 : 0;
  }

  method TO_JSON {
    my $json =
      JSON::PP->new->utf8->pretty->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}

1;
