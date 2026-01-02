package App::Schierer::HPFan::Person;

use strict;
use warnings;
use v5.42.0;
use utf8::all;
use Moo;
use Path::Tiny;
use Encode qw(encode_utf8);
use URI::Escape qw(uri_escape_utf8);
use App::Schierer::HPFan::Model::Gramps;
use App::Schierer::HPFan::View::Timeline;
use App::Schierer::HPFan::View::FamilyTree;
use PAGI::WebServer::Template;
use Log::Log4perl qw(get_logger);

has logger => (
  is => 'ro',
  default => sub { get_logger(__PACKAGE__) },
);

has gramps => (
    is => 'lazy',
    writer => '_set_gramps',
);

has template => (
    is => 'lazy',
);

has template_file => (
    is => 'ro',
    default => 'person/details.tt'
);

has navigation => (
    is => 'ro',
    predicate => 'has_navigation',
);

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

sub get_person_by_name {
    my ($self, $surname, $given_name) = @_;

    $self->logger->debug("Looking for person: $given_name $surname");

    # Search through all people
    my $people = $self->gramps->people;

    for my $person (values %$people) {
        my $primary_name = $person->primary_name;
        next unless $primary_name;

        my $p_surname_obj = $primary_name->primary_surname;
        my $p_surname = $p_surname_obj ? $p_surname_obj->surname : '';
        my $p_given = $primary_name->first_name // '';

        if ($p_surname eq $surname && $p_given eq $given_name) {
            $self->logger->debug("Found person: " . $person->gramps_id);
            return $person;
        }
    }

    $self->logger->warn("Person not found: $given_name $surname");
    return;
}

sub link_for_person {
    my ($self, $person) = @_;
    return '' unless $person;

    my $primary_name = $person->primary_name;
    return '' unless $primary_name;

    my $surname_obj = $primary_name->primary_surname;
    my $surname = $surname_obj ? uri_escape_utf8($surname_obj->surname) : '';
    my $given = uri_escape_utf8($primary_name->first_name // '');

    return "/Harrypedia/people/$surname/$given";
}

sub display_name_for_person {
    my ($self, $person) = @_;
    return 'Unknown' unless $person;

    my $primary_name = $person->primary_name;
    return 'Unknown' unless $primary_name;

    my $given = $primary_name->first_name // '';
    my $surname_obj = $primary_name->primary_surname;
    my $surname = $surname_obj ? $surname_obj->surname : '';

    my $name = join(' ', grep { $_ } ($given, $surname));
    return $name || 'Unknown';
}

sub prepare_person_data {
    my ($self, $person) = @_;

    return {
        gramps_id    => $person->gramps_id,
        gender       => $person->gender,
        display_name => $self->display_name_for_person($person),
    };
}

sub prepare_family_as_parent {
    my ($self, $family, $person) = @_;

    my $spouse_obj = $self->gramps->find_spouse($person, $family);

    my $spouse = $spouse_obj ? {
        display_name => $self->display_name_for_person($spouse_obj),
        link => $self->link_for_person($spouse_obj),
    } : undef;

    my @children;
    for my $child_ref (@{ $family->child_ref_list // [] }) {
        my $child_obj = $self->gramps->find_person_by_handle($child_ref->ref);
        if ($child_obj) {
            push @children, {
                display_name => $self->display_name_for_person($child_obj),
                link => $self->link_for_person($child_obj),
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

    my $father = $father_obj ? {
        display_name => $self->display_name_for_person($father_obj),
        link => $self->link_for_person($father_obj),
    } : undef;

    my $mother = $mother_obj ? {
        display_name => $self->display_name_for_person($mother_obj),
        link => $self->link_for_person($mother_obj),
    } : undef;

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
            gramps => $self->gramps,
            root_person => $person,
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
    my @families = map { $self->prepare_family_as_parent($_, $person) } @$families_raw;

    # Get families where this person is a child
    my $childof_raw = $self->gramps->find_families_as_child($person);
    my @childof = map { $self->prepare_family_as_child($_, $person) } @$childof_raw;

    # Generate family tree and timeline
    my $family_tree = $self->generate_family_tree($person);
    my $chart = $self->generate_timeline($person);

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
        title          => $display_name,
        current_year   => $current_year,
        css_files      => ['/css/gramps.css', '/css/navigation.css'],
        sidebar        => 1,
        navigation     => $navigation_html,
    };

    $self->logger->debug("Rendering template with " . scalar(@families) . " families and " . scalar(@childof) . " parent families");

    # Render template with layout
    my $html = $self->template->render(
        $self->template_file,
        $vars,
        { layout => 'layouts/default.tt' }
    );

    return $html;
}

1;
