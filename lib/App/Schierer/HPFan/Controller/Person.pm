package App::Schierer::HPFan::Controller::Person;

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
extends 'Thunderhorse::Controller';
with 'App::Schierer::HPFan::Role::Gramps';
with 'WebFramework::Role::Logger';

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

has pages_dir => (
  default => sub {
    my $self = shift;
    use FindBin;
    return path($FindBin::Bin)->parent->child('share/pages');
  },
  lazy => 1,
  is   => 'ro',
);

sub build ($self) {
  $self->ensure_ready();
  $self->register_routes($self->router);
}

async sub register_routes ($self, $router) {
  # Register person routes (higher priority than markdown)
  # Route with suffix for disambiguation
  $router->add(
    '/Harrypedia/people/:surname/:given/:suffix',
    {
      to => async sub ($self, $ctx, @args) {
        my $surname = $args[0] // 'Unknown';
        my $given   = $args[1] // 'Unknown';
        my $suffix  = $args[2] // '';
        return await $self->handle_person_route($ctx, $surname, $given,
          $suffix);
      },
      action => 'http.get',
    }
  );

  # Route without suffix
  $router->add(
    '/Harrypedia/people/:surname/:given',
    {
      to => async sub ($self, $ctx, @args) {
        my $surname = $args[0] // 'Unknown';
        my $given   = $args[1] // 'Unknown';
        return await $self->handle_person_route($ctx, $surname, $given);
      },
      action => 'http.get',
    }
  );
  foreach my $person (values $self->gramps->people->%*) {
    $self->logger->debug(
      sprintf('Person Controller got person "%s" from gramps model',
        $person->display_name)
    );
    $self->add_navigation_route(
      sprintf('/Harrypedia/people/%s', $person->name_as_link_path),
      $person->display_name, { order => 20 });
  }

}

async sub handle_person_route ($self, $ctx, $surname, $identifier, $suffix = '')
{
  my $path = $ctx->req->path;
  my $person;
  if ($surname && $identifier) {
    # URL decode the names
    $surname    =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $identifier =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $suffix     =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg if $suffix;

    # Determine if identifier is a gramps_id or a given name
    my $given_name;
    if ($identifier =~ /^I\d+$/) {
      # Looks like a gramps_id (e.g., I0209)
      $person = $self->gramps->find_person_by_id($identifier);
      # Extract given name from person if found
      if ($person && $person->primary_name) {
        $given_name = $person->primary_name->first_name // $identifier;
      }
      else {
        $given_name = $identifier;
      }
    }
    else {
      # Regular given name - may include suffix like "Sirius II"
      # Try to parse suffix from identifier if no explicit suffix parameter
      if (!$suffix
        && $identifier =~ /^(.+?)\s+(I+|IV|V|VI|IX|Jr\.?|Sr\.?|[IVX]+)$/i) {
        $given_name = $1;
        $suffix     = $2;
      }
      else {
        $given_name = $identifier;
      }

      $person = $self->get_person_by_name($surname, $given_name, $suffix);
    }

    if ($person) {
      # Check for static markdown content for this person
      my $static_content = '';

      # Build list of possible markdown filenames to try
      my @name_variants = ($identifier, $given_name);

      # If person has a suffix, also try given_name with suffix
      if ($person->primary_name && $person->primary_name->suffix) {
        my $person_suffix = $person->primary_name->suffix;
        push @name_variants, "$given_name $person_suffix";
      }

      # Try all name variants for markdown file
      for my $name_variant (@name_variants) {
        next unless $name_variant;
        my $person_md =
          $self->pages_dir->child("Harrypedia", "people", $surname,
          "$name_variant.md");
        if ($person_md->exists) {
          $static_content = $self->retrieve_rendered_markdown($person_md);
          last;
        }
      }

      my $html;
      eval {
        $html =
          $self->render_person_page_from_object($person, $static_content,
          $path);
      };

      if ($@) {
        $self->logger->error("Error rendering person page: $@");
        return $self->render_error(500, "Internal Server Error: $@");
      }

      return $html if $html;
    }
  }

  # Try as family listing
  my ($surname_only) = $path =~ m{^/Harrypedia/people/([^/]+)$};
  if ($surname_only) {
    $surname_only =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

    # Get the Family controller and delegate to it
    my $family_controller = $self->app->get_controller('Family');
    if ($family_controller) {
      my $html;
      eval {
        $html = await $family_controller->family_page($ctx, $surname_only);
      };
      if ($@) {
        $self->logger->error("Error rendering family page: $@");
      }
      return $html if $html;
    }
  }

  # Try markdown fallback before returning 404
  my $md_path = $path;
  $md_path =~ s|^/||;    # Remove leading slash
  my $md_file = $self->pages_dir->child("$md_path.md");

  if ($md_file->exists) {
    my $navigation_html = $self->render_navigation($path);

    # Render markdown content
    my $content = $self->retrieve_rendered_markdown($md_file);

    my $vars = {
      content => $content,
      title   => $self->parse_markdown_frontmatter($md_file)->{title}
        // (defined($person) ? $person->display_name : 'Unknown Person'),
      current_year => (localtime)[5] + 1900,
      css_files    => ['/css/navigation.css', '/css/gramps.css'],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo(),
    };

    return $self->render('page/markdown.tt', $vars);
  }

  # Not found
  return $self->render_error(404, 'Person or Family Not Found');
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

  $self->logger->debug("Rendering template with "
      . scalar(@families)
      . " families and "
      . scalar(@childof)
      . " parent families");

  # Render template
  return $self->render($self->template_file, $vars);
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
