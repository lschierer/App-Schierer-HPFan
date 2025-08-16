use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::DateHelper ;
require App::Schierer::HPFan::Model::Gramps::Surname;

class App::Schierer::HPFan::Model::Gramps::Name :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use overload
    '""'       => \&to_string,
    '.'        => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'fallback' => 0;

  field $_class     :param;
  field $call       : reader : param = undef;
  field $citation_list : param = [];
  field $date       : reader : param =
    undef;    # Can be daterange, datespan, dateval, or datestr
  field $display_as    : param = undef;
  field $famnick  : reader : param = undef;
  field $first_name      : reader : param = undef;
  field $group_as   : reader : param = undef;
  field $nick       : reader : param = undef;
  field $note_list     : param = [];
  field $private    : reader : param = 0;
  field $sort_as    : reader : param = undef;
  field $suffix     : reader : param = undef;
  field $surname_list   : param = [];
  field $title      : reader : param = undef;
  field $type       : reader : param = "Birth Name";
  field $alt :writer :reader;

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
  field @surnames;

  ADJUST {
    if(scalar @$surname_list){
      foreach my $surname ($surname_list->@*){
        my $sn = App::Schierer::HPFan::Model::Gramps::Surname->new(
          $surname->%*
        );
        if($sn){
          push @surnames, $sn;        }
      }
    }
  }

  method surnames() { [@surnames] }

  method note_refs()     { [@$note_list] }
  method citation_refs() { [@$citation_list] }

  method primary_surname() {
    for my $surname (@surnames) {
       return $surname if $surname->primary;
    }
    return scalar @surnames ? $surnames[0] : undef;
  }

  method display {
    return $display_as if $display_as;
    my @parts;
    push @parts, $first_name  if $first_name;
    push @parts, $call   if ($call and not $first_name);
    push @parts, "$nick" if ($nick and not $first_name);
    if (not scalar @parts) {
      push @parts, 'Unknown';
    }
    return join(' ', @parts);
  }

  method to_string {
    my @parts;

    push @parts, $title if $title;
    push @parts, $first_name if $first_name;

    if (my $primary_surname = $self->primary_surname) {
      push @parts, $primary_surname->to_string;
    }

    push @parts, $suffix if $suffix;

    my $name = join(" ", @parts) || "Unknown";

    if ($nick) {
      $name .= " \"$nick\"";
    }

    return $name;
  }
}

1;
