package App::Schierer::HPFan::Person;

use strict;
use warnings;
use v5.42.0;
use utf8::all;
use Moo;
with 'App::Schierer::HPFan::Role::GrampsMoo';
use Future::AsyncAwait;
use Path::Tiny;
use Encode      qw(encode_utf8);
use URI::Escape qw(uri_escape_utf8);
use App::Schierer::HPFan::Model::Gramps;
use App::Schierer::HPFan::View::Timeline;
use App::Schierer::HPFan::View::FamilyTree;
use PAGI::WebServer::Template;
use Log::Log4perl qw(get_logger);

has logger => (
  is      => 'ro',
  default => sub { get_logger(__PACKAGE__) },
);

has template => (is => 'lazy',);

has template_file => (
  is      => 'ro',
  default => 'person/details.tt'
);

has navigation => (
  is        => 'ro',
  predicate => 'has_navigation',
);

has family_handler => (
  is       => 'ro',
  required => 1,
);

async sub register_routes ($self, $nav, $router) {
  # Register person routes (higher priority than markdown)
  $router->get(
    '/Harrypedia/people/*' => async sub {
      my ($scope, $receive, $send) = @_;
      await $self->handle_person_route($scope, $receive, $send);
    }
  );
}

async sub handle_person_route ($self, $scope, $receive, $send) {
  my $path = $scope->{path};
  my ($surname, $given_name) = $path =~ m{^/Harrypedia/people/([^/]+)/(.+)$};

  if ($surname && $given_name) {
    # URL decode the names
    $surname    =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $given_name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

    eval {
      my $html = $self->render_person_page($surname, $given_name, '', $path);
      if ($html) {
        my $bytes = encode_utf8($html);
        await $send->({
          type    => 'http.response.start',
          status  => 200,
          headers => [['content-type', 'text/html; charset=utf-8']],
        });
        await $send->({
          type => 'http.response.body',
          body => $bytes,
          more => 0,
        });
        return;
      }
    };

    if ($@) {
      warn "Error rendering person page: $@";
      await $send->({
        type    => 'http.response.start',
        status  => 500,
        headers => [['content-type', 'text/plain']],
      });
      await $send->({
        type => 'http.response.body',
        body => "Internal Server Error: $@",
        more => 0,
      });
      return;
    }
  }

  # Try as family listing
  my ($surname_only) = $path =~ m{^/Harrypedia/people/([^/]+)$};
  if ($surname_only) {
    $surname_only =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

    eval {
      my $html =
        await $self->family_handler->render_family_page($surname_only, '',
        $path);
      if ($html) {
        my $bytes = encode_utf8($html);
        await $send->({
          type    => 'http.response.start',
          status  => 200,
          headers => [['content-type', 'text/html; charset=utf-8']],
        });
        await $send->({
          type => 'http.response.body',
          body => $bytes,
          more => 0,
        });
        return;
      }
    };
  }

  # Not found
  await $send->({
    type    => 'http.response.start',
    status  => 404,
    headers => [['content-type', 'text/plain']],
  });
  await $send->({
    type => 'http.response.body',
    body => 'Person or Family Not Found',
    more => 0,
  });
}

sub _build_gramps {
  my $self = shift;

  $self->logger->info("Initializing Gramps model...");

  my $gramps = App::Schierer::HPFan::Model::Gramps->new(
    gramps_export => path('share/data/gramps'),
    gramps_db     => path('share/grampsdb/sqlite.db'),
  );

  $self->logger->info("Importing Gramps data...");
  $gramps->execute_import();

  $self->logger->info("Building Gramps indexes...");
  $gramps->build_indexes();

  $self->logger->info("Gramps initialization complete");

  return $gramps;
}

sub _build_template {
  my $self = shift;

  return PAGI::WebServer::Template->new(
    template_dir => 'templates',
    include_path => ['templates', 'templates/partials']
  );
}

sub prepare_family_as_parent {
  my ($self, $family, $person) = @_;

  my $spouse_obj = $self->gramps->find_spouse($person, $family);

  my $spouse = $spouse_obj
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

sub prepare_family_as_child {
  my ($self, $family, $person) = @_;

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

  my $father = $father_obj
    ? {
    display_name => $self->display_name_for_person($father_obj),
    link         => $self->link_for_person($father_obj),
    }
    : undef;

  my $mother = $mother_obj
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

sub generate_family_tree {
  my ($self, $person) = @_;

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

sub generate_timeline {
  my ($self, $person) = @_;

  my $logger = get_logger(__PACKAGE__);

  eval {
    my $events = $self->gramps->find_events_for_person($person);

    #if (@$events) {
    #    my $timeline = App::Schierer::HPFan::View::Timeline->new(
    #        name   => $self->display_name_for_person($person),
    #        events => $events,
    #    );

    #    return $timeline->render();
    #}
  };

  if ($@) {
    $self->logger->error("Error generating timeline: $@");
  }

  return '<p>No timeline available</p>';
}

sub render_person_page {
  my ($self, $surname, $given_name, $static_content, $current_path) = @_;

  my $logger = get_logger(__PACKAGE__);

  my $person = $self->get_person_by_name($surname, $given_name);
  return unless $person;

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

  # Generate family tree and timeline
  my $family_tree = $self->generate_family_tree($person);
  my $chart       = $self->generate_timeline($person);

  # Get current year for footer
  my $current_year = (localtime)[5] + 1900;

  # Prepare display name for title
  my $display_name = $self->display_name_for_person($person);

  # Render navigation if available
  my $navigation_html = '';
  if ($self->has_navigation && $current_path) {
    $navigation_html = $self->navigation->render($current_path);
  }

  # Prepare template variables
  my $vars = {
    person         => $self->prepare_person_data($person),
    events         => $events,
    tags           => \@tag_names,
    families       => \@families,
    childof        => \@childof,
    family_tree    => $family_tree,
    chart          => $chart,
    static_content => $static_content,
    # Layout variables
    title        => $display_name,
    current_year => $current_year,
    css_files    => ['/css/gramps.css', '/css/navigation.css'],
    sidebar      => 1,
    navigation   => $navigation_html,
  };

  $self->logger->debug("Rendering template with "
      . scalar(@families)
      . " families and "
      . scalar(@childof)
      . " parent families");

  # Render template with layout
  my $html = $self->template->render($self->template_file, $vars,
    { layout => 'layouts/default.tt' });

  return $html;
}

1;
