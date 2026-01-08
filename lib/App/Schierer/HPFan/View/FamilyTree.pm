package App::Schierer::HPFan::View::FamilyTree;

use strict;
use warnings;
use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
with 'WebFramework::Role::Logger';
use GraphViz2;

has gramps => (
  is       => 'ro',
  required => 1,
);

has root_person => (
  is       => 'ro',
  required => 1,
);

has max_generations => (
  is      => 'ro',
  default => 10,
);

sub generate_svg {
  my ($self) = @_;

  my $graph = GraphViz2->new(
    global => {
      directed => 1,
    },
    graph => {
      rankdir => 'BT',    # Bottom to Top - root person at bottom
    },
    node => {
      shape    => 'box',
      style    => 'rounded',
      fontname => 'Arial',
    },
    edge => {
      arrowhead => 'none',
    },
  );

  # Track visited nodes to avoid duplicates
  my %visited;
  my %family_nodes;

  # Start with root person
  $self->_add_person_and_ancestors($graph, $self->root_person, \%visited,
    \%family_nodes, 0);

  # Generate SVG
  my $svg = '';
  $graph->run(driver => 'dot', format => 'svg', output_file => \$svg);

  # Post-process to remove GraphViz color formatting and add CSS classes
  $svg = $self->_clean_svg($svg);

  return $svg;
}

sub _add_person_and_ancestors {
  my ($self, $graph, $person, $visited, $family_nodes, $generation) = @_;

  return if $generation >= $self->max_generations;
  return unless $person;

  my $handle = $person->handle;
  return if $visited->{$handle};
  $visited->{$handle} = 1;

  # Add person node
  $self->_add_person_node($graph, $person);

  # Get parent families
  my $parent_families = $self->gramps->find_families_as_child($person);

  foreach my $family (@$parent_families) {
    next unless $family;

    # Create a family junction node
    my $family_id = "family_" . $family->handle;

    unless ($family_nodes->{$family_id}) {
      $graph->add_node(
        name   => $family_id,
        label  => '',
        shape  => 'point',
        width  => 0.1,
        height => 0.1,
        class  => 'family-node junction',
      );
      $family_nodes->{$family_id} = 1;
    }

    # Connect person to family junction
    $graph->add_edge(
      from  => $handle,
      to    => $family_id,
      class => 'family-node junction',
    );

    # Add parents
    my $father = $self->gramps->find_person_by_handle($family->father_handle);
    my $mother = $self->gramps->find_person_by_handle($family->mother_handle);

    if ($father) {
      $self->_add_person_and_ancestors($graph, $father, $visited,
        $family_nodes, $generation + 1);
      $graph->add_edge(
        from  => $family_id,
        to    => $father->handle,
        class => 'family-node junction',
      );
    }

    if ($mother) {
      $self->_add_person_and_ancestors($graph, $mother, $visited,
        $family_nodes, $generation + 1);
      $graph->add_edge(
        from  => $family_id,
        to    => $mother->handle,
        class => 'family-node junction',
      );
    }
  }
}

sub _add_person_node {
  my ($self, $graph, $person) = @_;

  my $primary_name = $person->primary_name;
  my $display_name = 'Unknown';
  my $url          = '#';

  if ($primary_name) {
    my $given       = $primary_name->first_name // '';
    my $surname_obj = $primary_name->primary_surname;
    my $surname     = $surname_obj ? $surname_obj->surname : '';

 # Build display name - use "Unknown (ID)" format when surname but no given name
    if ($surname && !$given) {
      my $gramps_id       = $person->gramps_id // '';
      my $unknown_with_id = $gramps_id ? "Unknown ($gramps_id)" : "Unknown";
      $display_name = "$unknown_with_id $surname";
    }
    else {
      $display_name = join(' ', grep {$_} ($given, $surname)) || 'Unknown';
    }

    # Build URL to person's detail page
    if ($surname) {
      use URI::Escape qw(uri_escape_utf8);
      my $surname_enc = uri_escape_utf8($surname);

      if ($given) {
        my $given_enc = uri_escape_utf8($given);
        $url = "/Harrypedia/people/$surname_enc/$given_enc";
      }
      else {
        # No given name - use gramps_id in URL
        my $gramps_id = $person->gramps_id // '';
        if ($gramps_id) {
          $url = "/Harrypedia/people/$surname_enc/$gramps_id";
        }
      }
    }
  }

  # Determine gender class
  my $gender_class = '';
  if ($person->gender eq 'M') {
    $gender_class = 'color-male';
  }
  elsif ($person->gender eq 'F') {
    $gender_class = 'color-female';
  }

  $graph->add_node(
    name  => $person->handle,
    label => $display_name,
    class => $gender_class,
    URL   => $url,
  );
}

sub _clean_svg {
  my ($self, $svg) = @_;
  $svg =~ s/<svg ([^>]*)width="[^"]*"/<svg $1/;
  $svg =~ s/<svg ([^>]*)height="[^"]*"/<svg $1/;
  $svg =~
s/<svg /<svg class="family-tree" preserveAspectRatio="xMidYMid meet" width="100%" height="100%" /;

  $svg =~ s/(stroke|fill)="black"//g;
  $svg =~ s/(stroke|fill)="none"//g;
  $svg =~ s/(stroke|fill)="white"//g;

  # Remove font colors
  $svg =~ s/color="[^"]*"//g;

  # Remove inline style attributes that conflict with CSS
  $svg =~ s/style="[^"]*"//g;

  # Ensure class attributes are preserved and properly formatted
  # GraphViz2 should add class attributes, but let's make sure they're there

  return $svg;
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::View::FamilyTree - Generate ancestor family trees using GraphViz2

=head1 SYNOPSIS

    use App::Schierer::HPFan::View::FamilyTree;

    my $tree = App::Schierer::HPFan::View::FamilyTree->new(
        gramps => $gramps_model,
        root_person => $person,
        max_generations => 10,
    );

    my $svg = $tree->generate_svg();

=head1 DESCRIPTION

Generates SVG family tree diagrams showing ancestors of a person, using
GraphViz2 for layout and CSS for styling.

=cut
