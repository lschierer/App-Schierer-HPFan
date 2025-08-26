use v5.42;
use utf8::all;
use experimental qw(class);
require App::Schierer::HPFan::Model::Gramps::Surname;
require App::Schierer::HPFan::Model::CustomDate;

class App::Schierer::HPFan::Model::Gramps::Name :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  use overload
    '""'       => \&to_string,
    '.'        => \&to_string,
    'bool'     => sub { $_[0]->_isTrue() },
    'fallback' => 0;

  field $data : param;

  field $_class        ;
  field $alt          : writer : reader;
  field $call          : reader  = undef;
  field $date          : reader  = undef;
  field $display_as    = undef;
  field $famnick      : reader  = undef;
  field $first_name   : reader  = undef;
  field $group_as     : reader  = undef;
  field $nick         : reader  = undef;
  field $private      : reader  = 0;
  field $sort_as      : reader  = undef;
  field $suffix       : reader  = undef;
  field $title        : reader  = undef;
  field $type         : reader  = "Birth Name";

  field $surnames = [];
  field $citation_list  = [];
  field $note_list     = [];
  field $surname_list  = [];


  ADJUST {
    $call       = $data->{call};
    $date       = App::Schierer::HPFan::Model::CustomDate->new(text => $data->{date});
    $display_as = $data->{display_as};
    $famnick    = $data->{famnick};
    $first_name = $data->{first_name};
    $group_as   = $data->{group_as};
    $nick       = $data->{nick};
    $private    = $data->{private} ? 1 : 0;
    $sort_as    = $data->{sort_as};
    $suffix     = $data->{suffix};


    foreach my $item ($data->{citation_list}->@*){
      push @$citation_list, $item;
    }

    foreach my $item ($data->{note_list}->@*){
      push @$note_list, $item;
    }

    foreach my $item ($data->{surname_list}->@*) {
      push @{ $surnames }, App::Schierer::HPFan::Model::Gramps::Surname->new( data => $item);
    }
  }

  method surnames() { [@$surnames] }

  method note_refs()     { [@$note_list] }
  method citation_list() { [@$citation_list] }

  method primary_surname() {
    for my $surname (@$surnames) {
      return $surname if $surname->primary;
    }
    return scalar @$surnames ? $surnames->[0] : undef;
  }

  method display {
    return $display_as if $display_as;
    my @parts;
    push @parts, $first_name if $first_name;
    push @parts, $call       if ($call and not $first_name);
    push @parts, "$nick"     if ($nick and not $first_name);
    if (not scalar @parts) {
      push @parts, 'Unknown';
    }
    return join(' ', @parts);
  }

  method to_string {
    my @parts;

    push @parts, $title      if $title;
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
