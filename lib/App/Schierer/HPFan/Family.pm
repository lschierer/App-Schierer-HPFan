package App::Schierer::HPFan::Family;

use strict;
use warnings;
use v5.42.0;
use utf8::all;
use Moo;
with 'App::Schierer::HPFan::Role::Gramps';
use Future::AsyncAwait;
use Path::Tiny;
use Encode      qw(encode_utf8);
use URI::Escape qw(uri_escape_utf8);
use App::Schierer::HPFan::Model::Gramps;
use PAGI::WebServer::Template;
use Log::Log4perl qw(get_logger);

has logger => (
  is      => 'ro',
  default => sub { get_logger(__PACKAGE__) },
);

has template => (is => 'lazy',);

has template_file => (
  is      => 'ro',
  default => 'family/details.tt'
);

has navigation => (
  is        => 'ro',
  predicate => 'has_navigation',
);

has site_logo => (
  is      => 'ro',
  default => '',
);

async sub register_routes ($self, $nav, $router) {
  # Add special "Unknown" surname route
  $nav->add_route(
    '/Harrypedia/people/Unknown',
    'Genealogical Gaps - Unknown Surnames',
    { order => 999 }
  );

  # Register routes for all family surnames and their members
  my $surnames = await $self->get_all_surnames();
  for my $surname (@$surnames) {
    my $route_path = '/Harrypedia/people/' . $surname;
    $nav->add_route($route_path, "$surname Family", { order => 100 });

    # Register individual family members
    my $family_members = await $self->get_people_by_surname($surname);
    for my $person (@$family_members) {
      my $primary_name = $person->primary_name;
      next unless $primary_name;

      my $given = $primary_name->first_name // '';

      # For people with unknown given names, use gramps_id in URL
      my $identifier;
      my $display_name;
      if ($given) {
        $identifier = $given;
        $display_name = $given;
      }
      else {
        # No given name - use gramps_id in URL for disambiguation
        # but show human-friendly name like "Unknown (I0209)"
        $identifier = $person->gramps_id;
        $display_name = $identifier ? "Unknown ($identifier)" : 'Unknown';
      }

      my $person_route = "/Harrypedia/people/$surname/$identifier";
      $nav->add_route($person_route, $display_name, { order => 110 });
    }
  }

  # Register people with unknown surnames
  my $unknown_people = await $self->get_people_with_unknown_surname();
  for my $person (@$unknown_people) {
    my $primary_name = $person->primary_name;
    my $given        = $primary_name ? ($primary_name->first_name // '') : '';

    my $display_name = $given || $person->gramps_id || 'Unknown';
    my $person_route = "/Harrypedia/people/Unknown/$display_name";
    $nav->add_route($person_route, $display_name, { order => 110 });
  }
}

sub _build_template {
  my $self = shift;

  return PAGI::WebServer::Template->new(
    template_dir => 'templates',
    include_path => ['templates', 'templates/partials']
  );
}

# Build family tree starting from root ancestors
sub build_family_tree {
  my ($self, $family_members) = @_;

  # Find root ancestors (those without parents in this family)
  my @roots;
  for my $person (@$family_members) {
    unless ($self->_has_parents_in_family($person, $family_members)) {
      push @roots, $person;
    }
  }

  # Sort roots by birth date
  @roots = sort { $self->_compare_birth_dates($a, $b) } @roots;

  # Build tree for each root
  my @tree;
  for my $root (@roots) {
    push @tree, $self->_build_person_subtree($root, $family_members);
  }

  return \@tree;
}

# Check if person has parents in the given family
sub _has_parents_in_family {
  my ($self, $person, $family_members) = @_;

  my %family_handles = map { $_->handle => 1 } @$family_members;

  my $parent_families = $self->gramps->find_families_as_child($person);

  for my $family (@$parent_families) {
    my $father = $self->gramps->find_person_by_handle($family->father_handle);
    my $mother = $self->gramps->find_person_by_handle($family->mother_handle);

    # Check if either parent is in this family
    if ($father && exists $family_handles{ $father->handle }) {
      return 1;
    }
    if ($mother && exists $family_handles{ $mother->handle }) {
      return 1;
    }
  }

  return 0;
}

# Build subtree for a person and their descendants
sub _build_person_subtree {
  my ($self, $person, $family_members) = @_;

  my $node = {
    person   => $person,
    children => [],
  };

  # Get children of this person who are in the family
  my $children = $self->_get_children_in_family($person, $family_members);

  # Sort children by birth date
  my @sorted_children = sort { $self->_compare_birth_dates($a, $b) } @$children;

  # Recursively build subtrees for children
  for my $child (@sorted_children) {
    push @{ $node->{children} },
      $self->_build_person_subtree($child, $family_members);
  }

  return $node;
}

# Get children of a person who belong to the family
sub _get_children_in_family {
  my ($self, $person, $family_members) = @_;

  my %family_handles = map { $_->handle => 1 } @$family_members;
  my @children;

  # Get the target surname from the person
  my $target_surname = $self->_get_person_surname($person);

  my $families = $self->gramps->find_families_as_parent($person);

  for my $family (@$families) {
    # Get both parents
    my $father = $self->gramps->find_person_by_handle($family->father_handle);
    my $mother = $self->gramps->find_person_by_handle($family->mother_handle);

    # Get surnames for both parents
    my $father_surname = $father ? $self->_get_person_surname($father) : '';
    my $mother_surname = $mother ? $self->_get_person_surname($mother) : '';

    # Determine if we should include children from this family
    my $include_children = 0;

    if ( $father_surname eq $target_surname
      && $mother_surname eq $target_surname) {
# Both parents have the same surname - only include if this person is the father
      $include_children = 1 if ($father && $father->handle eq $person->handle);
    }
    elsif ($father_surname eq $target_surname
      || $mother_surname eq $target_surname) {
      # Only one parent has the surname - include if this person is that parent
      if ( $father
        && $father->handle eq $person->handle
        && $father_surname eq $target_surname) {
        $include_children = 1;
      }
      elsif ($mother
        && $mother->handle eq $person->handle
        && $mother_surname eq $target_surname) {
        $include_children = 1;
      }
    }

    next unless $include_children;

    for my $child_ref (@{ $family->child_ref_list // [] }) {
      my $child = $self->gramps->find_person_by_handle($child_ref->ref);

      if ($child && exists $family_handles{ $child->handle }) {
        push @children, $child;
      }
    }
  }

  return \@children;
}

# Helper to get a person's surname
sub _get_person_surname {
  my ($self, $person) = @_;

  return '' unless $person;

  my $primary_name = $person->primary_name;
  return '' unless $primary_name;

  my $surname_obj = $primary_name->primary_surname;
  return '' unless defined($surname_obj);

  return $surname_obj->surname // '';
}

# Compare two people by birth date
sub _compare_birth_dates {
  my ($self, $person_a, $person_b) = @_;

  my $events_a = $self->gramps->find_events_for_person($person_a);
  my $events_b = $self->gramps->find_events_for_person($person_b);

  my ($birth_a) = grep { $_->type eq 'Birth' } @$events_a;
  my ($birth_b) = grep { $_->type eq 'Birth' } @$events_b;

  return 0 unless $birth_a || $birth_b;
  return -1 if $birth_a  && !$birth_b;
  return 1  if !$birth_a && $birth_b;

  my $date_a = $birth_a->date;
  my $date_b = $birth_b->date;

  return 0 unless $date_a || $date_b;
  return -1 if $date_a  && !$date_b;
  return 1  if !$date_a && $date_b;

  return $date_a->year <=> $date_b->year;
}

# Render family listing page
async sub render_family_page {
  my ($self, $surname, $static_content, $current_path) = @_;

  my $is_unknown = ($surname eq 'Unknown');
  my $family_members;

  if ($is_unknown) {
    $family_members = await $self->get_people_with_unknown_surname();
  }
  else {
    $family_members = await $self->get_people_by_surname($surname);
  }

  return unless @$family_members;

  # Build family tree
  my $family_tree = $self->build_family_tree($family_members);

  # Prepare person data for all members
  my @prepared_tree;
  for my $root (@$family_tree) {
    push @prepared_tree, $self->_prepare_tree_node($root);
  }

  # Get current year for footer
  my $current_year = (localtime)[5] + 1900;

  # Determine page title
  my $title =
    $is_unknown
    ? 'Genealogical Gaps - People with Unknown Surnames'
    : "$surname Family";

  # Render navigation if available
  my $navigation_html = '';
  if ($self->has_navigation && $current_path) {
    $navigation_html = $self->navigation->render($current_path);
  }

  # Prepare template variables
  my $vars = {
    surname        => $surname,
    is_unknown     => $is_unknown,
    family_tree    => \@prepared_tree,
    member_count   => scalar(@$family_members),
    static_content => $static_content,
    # Layout variables
    title        => $title,
    current_year => $current_year,
    css_files    => ['/css/gramps.css', '/css/navigation.css'],
    sidebar      => 1,
    navigation   => $navigation_html,
    site_logo    => $self->site_logo,
  };

  # Render template with layout
  my $html = $self->template->render($self->template_file, $vars,
    { layout => 'layouts/default.tt' });

  return $html;
}

# Prepare tree node with person data
sub _prepare_tree_node {
  my ($self, $node) = @_;

  return {
    person   => $self->prepare_person_data($node->{person}),
    children => [map { $self->_prepare_tree_node($_) } @{ $node->{children} }],
  };
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Family - Family listing and tree generation

=head1 SYNOPSIS

    use App::Schierer::HPFan::Family;

    my $family = App::Schierer::HPFan::Family->new;

    my $html = $family->render_family_page('Potter', $static_content, $path);

=head1 DESCRIPTION

Handles family listing pages showing all people with a given surname,
builds hierarchical family trees, and provides special handling for
people with unknown surnames.

=cut
