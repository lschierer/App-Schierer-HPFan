package App::Schierer::HPFan::Controller::Family;
# cspell: disable

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
extends 'WebFramework::Controller::Base';
with 'App::Schierer::HPFan::Role::Gramps';

use Future::AsyncAwait;
use Path::Tiny;
use Encode      qw(encode_utf8);
use URI::Escape qw(uri_escape_utf8);

sub build ($self) {
  $self->SUPER::build();
  $self->ensure_ready();
  $self->register_routes($self->router);
}

sub register_routes ($self, $router) {
  my $surnames = $self->get_all_surnames->get;
  $self->logger->debug(
    sprintf('retrieved %s surnames from Gramps role', scalar(@{$surnames})));

  foreach my $surname ($surnames->@*) {
    my $route = sprintf('/Harrypedia/people/%s', $surname);

    $self->logger->debug(
      sprintf('Family Controller registering route for surname "%s"', $surname)
    );

    # Register the router route
    $router->add(
      $route,
      {
        to => async sub ($self, $ctx, @args) {
          return await $self->family_page($ctx, $surname);
        },
        action => 'http.*',
      }
    );

    # Add to navigation
    $self->add_navigation_route(
      $route,
      sprintf('%s Family', $surname),
      { order => 20 }
    );
  }
}

async sub family_page ($self, $ctx, $surname) {
  my $current_path = $ctx->req->path;

  my $is_unknown = ($surname eq 'Unknown');
  my $family_members;

  if ($is_unknown) {
    $family_members = await $self->get_people_with_unknown_surname();
  }
  else {
    $family_members = await $self->get_people_by_surname($surname);
  }

  if (@$family_members) {
    $self->logger->debug(sprintf(
      'family with surname "%s" has %s members.',
      $surname, scalar(@$family_members)
    ));
  }
  else {
    $self->logger->warn(
      sprintf('family with surname "%s" has no members.', $surname));
    return;
  }

  # Build family tree
  my $family_tree = $self->build_family_tree($family_members);

  # Prepare person data for all members
  my @prepared_tree;
  for my $root (@$family_tree) {
    push @prepared_tree, $self->_prepare_tree_node($root);
  }

  # Check for static markdown content for this family
  my $static_content = '';
  my $family_md =
    $self->pages_dir->child('Harrypedia', 'people', $surname, "index.md");
  $family_md //=
    $self->pages_dir->child('Harrypedia', 'people', "${surname}.md");
  if ($family_md->exists) {
    $self->logger->debug("found static content at '$family_md'");
    $static_content = $self->retrieve_rendered_markdown($family_md);
  }
  else {
    $self->logger->debug("no static content at '$family_md'");
  }

  # Get current year for footer
  my $current_year = (localtime)[5] + 1900;

  # Determine page title
  my $title =
    $is_unknown
    ? 'Genealogical Gaps - People with Unknown Surnames'
    : "$surname Family";

  # Render navigation
  my $navigation_html = $self->render_navigation($current_path);

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
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo(),
  };

  return $self->template('family/details.tt', $vars);
}

# Build family tree starting from root ancestors
sub build_family_tree ($self, $family_members) {
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
sub _has_parents_in_family ($self, $person, $family_members) {
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
sub _build_person_subtree ($self, $person, $family_members) {
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
sub _get_children_in_family ($self, $person, $family_members) {
  my %family_handles = map { $_->handle => 1 } @$family_members;
  my @children;

  # Get the target surname from the person
  my $target_surname = $person->get_surname // 'Unknown';

  my $families = $self->gramps->find_families_as_parent($person);

  for my $family (@$families) {
    # Get both parents
    my $father = $self->gramps->find_person_by_handle($family->father_handle);
    my $mother = $self->gramps->find_person_by_handle($family->mother_handle);

    # Get surnames for both parents
    my $father_surname = $father ? $father->get_surname : '';
    $father_surname //= 'Unknown';
    my $mother_surname = $mother ? $mother->get_surname : '';
    $mother_surname //= 'Unknown';

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

# Compare two people by birth date
sub _compare_birth_dates ($self, $person_a, $person_b) {
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

# Prepare tree node with person data
sub _prepare_tree_node ($self, $node) {
  return {
    person   => $self->prepare_person_data($node->{person}),
    children => [map { $self->_prepare_tree_node($_) } @{ $node->{children} }],
  };
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Controller::Family - Family listing and tree generation controller

=head1 DESCRIPTION

Thunderhorse controller for handling family listing pages showing all people
with a given surname, builds hierarchical family trees, and provides special
handling for people with unknown surnames.

=cut
