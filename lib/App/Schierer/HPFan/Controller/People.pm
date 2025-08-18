use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::People {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';
  use Carp;

  my $logger;

  sub register($self, $app, $config //= {}) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    $app->helper(
      people => sub ($c) {
        return $app->gramps->people;
      }
    );

    $app->helper(
      person_by_handle => sub($c, $handle) {
        return $app->gramps->find_person_by_handle($handle);
      }
    );

    $app->helper(
      person_by_id => sub($c, $id) {
        return $app->gramps->find_person_by_id($id);
      }
    );

    $app->helper(
      link_target_for_person => sub ($c, $person) {
        if (not defined $person) {
          $logger->error("cannot return link for undefined person!!");
          return '';
        }
        my $name = $person->primary_name();
        my $last;
        if ($name) {
          $last = $name->primary_surname;
        }

        my $route = sprintf('%s %s/%s %s',
          $last->prefix  ? $last->prefix  : '',
          $last->surname ? $last->surname : 'Unknown',
          $name
          ? $name->display ne 'Unknown'
              ? $name->display
              : $person->id
          : $person->id,
          $name->suffix ? $name->suffix : '',
        );
        $route =~ s/^\s+|\s+$//g;
        $route = '/Harrypedia/people/' . $route;

        return $route;
      }
    );

    $app->plugins->on(
      'gramps_initialized' => sub($c, $gramps) {
        $logger->debug(__PACKAGE__ . ' gramps_initialized sub start');
        $self->_register_routes($app);
      }
    );

    if ($app->config('gramps_initialized')) {
      $logger->debug(__PACKAGE__ . ' detects gramps_initialized from config');
      $self->_register_routes($app);
    }
  }

  sub _register_routes ($self, $app) {

    $logger->debug(__PACKAGE__ . '_register_routes start');
    foreach my $person (sort { return $a->id cmp $b->id }
      values %{ $app->gramps->people }) {

      my $route = $app->link_target_for_person($person) // '/';
      my $rn    = $route =~ s/ /_/gr;
      my $title = $person->display_name();

      $logger->debug(sprintf(
        'adding route %s for %s with id %s',
        $route, $title, $person->id
      ));

      $app->routes->get($route,=> { id => $person->id, })
        ->to(controller => 'People', action => 'person_details')
        ->name($rn);
      $app->add_navigation_item({
        title => $title,
        path  => $route,
        order => 1,
      });
    }

  }

  sub person_details ($c) {
    $logger->debug("start of person_details method");

    my $rp = $c->req->url->path->to_string;
    # Remove trailing slash from pages
    if ($rp =~ qr{/$}) {
      my $canonical = $rp;
      $canonical =~ s{/$}{};
      return $c->redirect_to($canonical, 301);
    }

    my $id = $c->param('id');
    my $staticContent;

    if ($id) {
      $logger->debug("person_details detects id $id");
      my $person = $c->app->person_by_id($id);
      if ($person) {
        $logger->debug("found person for id $id");

        $c->stash(person   => $person);
        $c->stash(layout   => 'default');
        $c->stash(template => 'person/details');
        $c->stash(title    => $person->display_name());
        $c->stash(chart    => $c->generate_ancestor_chart($person));

        my @events = @{ $c->app->gramps->find_events_for_person($person) };
        $logger->debug("recieved events " . Data::Printer::np(@events));
        $c->stash(events => \@events);

        my $route = $c->link_target_for_person($person);
        $staticContent = $c->app->config('distDir')->child("pages${route}");
        if (-d $staticContent) {
          $staticContent = sprintf('%s/index.md', $staticContent);
        }
        else {
          $staticContent = sprintf('%s.md', $staticContent);
        }
        if (-f -r $staticContent) {
          my $markdown = Mojo::File->new($staticContent)->slurp('UTF-8');
          #get rid of front matter, just discard it.
          $markdown =~ s/^---\s*\n(.*?)\n---\s*\n//s;
          my $content = $c->render_markdown_snippet($markdown);
          $c->stash(staticContent => $content);
        }
        else {
          $logger->debug("static content not found at $staticContent");
        }

        return $c->render;
      }
    }
    return $c->reply->not_found;
  }

  sub generate_ancestor_chart($self, $person) {
    my $graph = GraphViz->new(
      directed => 1,
      title    => "Ancestor Chart for "
        . $person->display_name(),    # this line doesn't seem to get used??
      layout  => 'dot',
      rankdir => 'TB',          # top to bottom seems to do what I want better??
      bgcolor => 'transparent'
      ,    # Transparent background -- this line isn't used, but doesn't matter
      node => {
        fillcolor => 'transparent'
        ,   # Transparent background -- this line isn't used, but doesn't matter
        shape => 'box',
        style => 'filled',
      },

    );
    $logger->debug('Graphviz initialized');

    my %visited;
    my %generation_map;    # Track generation levels

    # Build the tree and track generations
    $self->_add_ancestors_to_graph($graph, $person, \%visited, 0,
      \%generation_map);
    $logger->debug("ready to render svg " . Data::Printer::np($graph));
    my $svg = $graph->as_svg;
    $logger->debug(sprintf('generated svg'));
    $svg =~ s/(stroke|fill)="black"//g;
    $svg =~ s/(stroke|fill)="none"//g;
    $svg =~ s/<svg ([^>]*)width="[^"]*"/<svg $1/;
    $svg =~ s/<svg ([^>]*)height="[^"]*"/<svg $1/;
    $svg =~
s/<svg /<svg preserveAspectRatio="xMidYMid meet" width="100%" height="100%" /;
    return $svg;
  }

  sub _add_ancestors_to_graph($self, $graph, $person, $visited, $generation,
    $generation_map) {
    my $person_id = $person->handle;
    $logger->debug(sprintf('person with person id %s', $person->id));
    return if $visited->{$person_id};
    $visited->{$person_id} = 1;

    $generation_map->{$person_id} = $generation;

    # Determine gender-based styling

    my $gender = $person->gender;
    $logger->debug("detected gender $gender for person id " . $person->id);

    # Add person node
    my $label = $person->display_name();
    $graph->add_node(
      $person_id,
      label => $label,
      href  => $self->app->link_target_for_person($person),
      class => $gender eq 'M' ? 'color-male'
      : $gender eq 'F' ? 'color-female'
      :                  '',
    );

    # Process families (parents)
    foreach my $family_handle ($person->child_of_refs->@*) {
      my $family = $self->app->gramps->families->{$family_handle};
      next unless $family;
      my $child_ref;
      foreach my $cr (@{ $family->child_refs() }) {
        if ($cr->{handle} eq $person->handle) {
          $child_ref = $cr;
          last;
        }
      }
      if (  ($child_ref->{father_rel} && $child_ref->{father_rel} eq 'Foster')
        and ($child_ref->{mother_rel} && $child_ref->{mother_rel} eq 'Foster'))
      {
        next;
      }

      # Create invisible family node as connection point
      my $family_node = "family_$family_handle";
      $graph->add_node(
        $family_node,
        shape  => 'point',
        width  => 0.05,
        height => 0.05,
        class  => 'family-node junction',
      );

      # Connect child to family point
      $graph->add_edge($family_node, $person_id,
          class => $gender eq 'M' ? 'color-male'
        : $gender eq 'F' ? 'color-female'
        :                  '',);

      # Add parents and connect to family point
      if (my $father_handle = $family->father_ref) {
        my $father = $self->people->{$father_handle};
        if ($father) {
          $self->logger->debug("found father $father_handle " . $father->id);
          $self->_add_ancestors_to_graph($graph, $father, $visited,
            $generation + 1,
            $generation_map);
          $graph->add_edge($father->handle, $family_node,
            class => 'color-male',);
        }
      }

      if (my $mother_handle = $family->mother_ref) {
        my $mother = $self->people->{$mother_handle};
        if ($mother) {
          $self->logger->debug("found mother $mother_handle " . $mother->id);
          $self->_add_ancestors_to_graph($graph, $mother, $visited,
            $generation + 1,
            $generation_map);
          $graph->add_edge($mother->handle, $family_node,
            class => 'color-female',);
        }
      }
    }
  }

}
1;

__END__
