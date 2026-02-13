package App::Schierer::HPFan::Controller::Person;
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
use App::Schierer::HPFan::View::Timeline;
use App::Schierer::HPFan::View::FamilyTree;

has template_file => (
  is      => 'ro',
  default => 'person/details.tt'
);



sub build ($self) {
  $self->ensure_ready();
  $self->register_routes($self->router);
}

async sub register_routes ($self, $router) {
  # Register specific routes for each person in Gramps
  my $people = $self->gramps->people;
  
  foreach my $person (values %$people) {
    my $route = sprintf('/Harrypedia/people/%s', $person->name_as_link_path);
    
    $self->logger->debug(sprintf(
      'Person Controller registering route for "%s" at %s',
      $person->display_name, $route
    ));
    
    # Register the route
    $router->add(
      $route,
      {
        to => async sub ($self, $ctx, @args) {
          return await $self->person_page($ctx, $person);
        },
        action => 'http.*',
      }
    );
    
    # Add to navigation
    $self->add_navigation_route($route, $person->display_name, { order => 21 });
  }
}

async sub person_page ($self, $ctx, $person) {
  my $path = $ctx->req->path;
  
  $self->logger->info(sprintf(
    'Controller::Person rendering "%s" for request "%s"',
    $person->display_name, $path
  ));
  
  # Check for static markdown content for this person
  my $static_content = '';
  my $surname_obj = $person->primary_name->primary_surname;
  my $surname = $surname_obj ? $surname_obj->surname : 'Unknown';
  my $given_name = $person->primary_name->first_name // 'Unknown';
  
  # Build list of possible markdown filenames to try
  my @name_variants = ($given_name);
  
  # If person has a suffix, also try given_name with suffix
  if ($person->primary_name && $person->primary_name->suffix) {
    my $person_suffix = $person->primary_name->suffix;
    push @name_variants, "$given_name $person_suffix";
  }
  
  # Try all name variants for markdown file
  for my $name_variant (@name_variants) {
    next unless $name_variant;
    my $person_md = $self->pages_dir->child(
      "Harrypedia", "people", $surname, "$name_variant.md"
    );
    if ($person_md->exists) {
      $static_content = $self->retrieve_rendered_markdown($person_md);
      last;
    }
  }
  
  my $html;
  eval {
    $html = $self->render_person_page_from_object($person, $static_content, $path);
  };
  
  if ($@) {
    $self->logger->error("Error rendering person page: $@");
    return $self->render_error(500, "Internal Server Error: $@");
  }
  
  return $html if $html;
  
  # Shouldn't reach here, but just in case
  return $self->render_error(404, 'Person Not Found');
}

sub prepare_family_as_parent ($self, $family, $person) {
  my $spouse_obj = $self->gramps->find_spouse($person, $family);

  my $spouse =
    $spouse_obj
    ? {
    display_name => $self->display_name_for_person($spouse_obj),
    link         => $self->link_for_person($spouse_obj),
    }
    : undef;

  my @children;
  for my $child_ref (@{ $family->child_ref_list // [] }) {
    my $child_obj = $self->gramps->find_person_by_handle($child_ref->ref);
    if ($child_obj) {
      push @children,
        {
        display_name => $self->display_name_for_person($child_obj),
        link         => $self->link_for_person($child_obj),
        };
    }
  }

  return {
    spouse   => $spouse,
    children => \@children,
    type     => $family->type // 'Unknown',
  };
}

sub prepare_family_as_child ($self, $family, $person) {
  # Find this person's child reference to get relationship types
  my $child_ref;
  for my $cr (@{ $family->child_ref_list // [] }) {
    if ($cr->ref eq $person->handle) {
      $child_ref = $cr;
      last;
    }
  }

  my $father_obj = $self->gramps->find_person_by_handle($family->father_handle);
  my $mother_obj = $self->gramps->find_person_by_handle($family->mother_handle);

  my $father =
    $father_obj
    ? {
    display_name => $self->display_name_for_person($father_obj),
    link         => $self->link_for_person($father_obj),
    }
    : undef;

  my $mother =
    $mother_obj
    ? {
    display_name => $self->display_name_for_person($mother_obj),
    link         => $self->link_for_person($mother_obj),
    }
    : undef;

  return {
    father => $father,
    mother => $mother,
    type   => $family->type // 'Unknown',
    frel   => $child_ref ? $child_ref->frel : '',
    mrel   => $child_ref ? $child_ref->mrel : '',
  };
}

sub generate_family_tree ($self, $person) {
  my $svg;
  eval {
    my $tree = App::Schierer::HPFan::View::FamilyTree->new(
      gramps          => $self->gramps,
      root_person     => $person,
      max_generations => 10,
    );

    $svg = $tree->generate_svg();
  };

  if ($@) {
    $self->logger->error("Error generating family tree: $@");
    return '<p>Family tree unavailable</p>';
  }

  return $svg;
}

sub render_person_page_from_object ($self, $person, $static_content,
  $current_path) {
  # Get events
  my $events = $self->gramps->find_events_for_person($person);

  # Get tags as strings
  my $tags_hash = $self->gramps->tags;
  my @tag_names;
  for my $tag_handle (@{ $person->tag_list // [] }) {
    if (my $tag_obj = $tags_hash->{$tag_handle}) {
      push @tag_names, $tag_obj->name;
    }
  }

  # Get families where this person is a parent
  my $families_raw = $self->gramps->find_families_as_parent($person);
  my @families =
    map { $self->prepare_family_as_parent($_, $person) } @$families_raw;

  # Get families where this person is a child
  my $childof_raw = $self->gramps->find_families_as_child($person);
  my @childof =
    map { $self->prepare_family_as_child($_, $person) } @$childof_raw;

  # Generate family tree
  my $family_tree = $self->generate_family_tree($person);

  # Get current year for footer
  my $current_year = (localtime)[5] + 1900;

  # Prepare display name for title
  my $display_name = $self->display_name_for_person($person);

  # Render navigation
  my $navigation_html = $self->render_navigation($current_path);

  # Prepare template variables
  my $vars = {
    person         => $self->prepare_person_data($person),
    events         => $events,
    tags           => \@tag_names,
    families       => \@families,
    childof        => \@childof,
    family_tree    => $family_tree,
    static_content => $static_content,
    # Layout variables
    title        => $display_name,
    current_year => $current_year,
    css_files    => ['/css/gramps.css', '/css/navigation.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo(),
  };

  $self->logger->debug(
        "Rendering template with "
      . scalar(@families)
      . " families and "
      . scalar(@childof)
      . " parent families");

  # Render template
  return $self->template($self->template_file, $vars);
}

sub render_person_page ($self, $surname, $given_name, $static_content,
  $current_path) {
  my $person = $self->get_person_by_name($surname, $given_name);
  return unless $person;

  return $self->render_person_page_from_object($person, $static_content,
    $current_path);
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Controller::Person - Person detail page controller

=head1 DESCRIPTION

Thunderhorse controller for handling individual person detail pages from the
genealogical database. Displays person information, events, family relationships,
and family trees.

=cut
