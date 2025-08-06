use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::Families {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';
  use Log::Log4perl;
  require Data::Printer;
  use Carp;

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(__PACKAGE__ . " register function");

    $app->helper(
      family_by_handle => sub($c, $handle) {
        return $app->gramps->families->{$handle};
      }
    );

    $app->helper(
      family_by_id => sub($c, $id) {
        return $app->gramps->find_family_by_id($id);
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
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug(__PACKAGE__ . '_register_routes start');
    my %family_names;
    foreach my $person (sort { return $a->id cmp $b->id; }
      values %{ $app->gramps->people }) {
      $logger->debug(
        sprintf('inspecting %s for presence of family name', $person->id));
      my $name = $person->primary_name;
      if ($name) {
        my $sn = $name->primary_surname;
        if ($sn && length($sn->display_name)) {
          $logger->debug(sprintf(
            'found family name "%s" in person %s',
            $sn->display_name, $person->id
          ));
          $family_names{ $sn->display_name }++;
        }
      }
    }

    foreach my $family_name (sort keys %family_names) {
      my $route = sprintf('/Harrypedia/people/%s', $family_name);
      my $rn    = $route =~ s/ /_/gr;
      $logger->debug(sprintf('adding route %s for %s.', $route, $family_name));

      $app->routes->get($route,=> { family_name => $family_name, })
        ->to(controller => 'Families', action => 'family_details')
        ->name($rn);
      $app->add_navigation_item({
        title => $family_name,
        path  => $route,
        order => 1,
      });
    }
  }

  sub family_details ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug("start of family_details method");
    my $family_name = $c->param('family_name');
    my $staticContent;
    $c->stash(family_name => $family_name);
    $c->stash(title       => "The $family_name Family");
    $c->stash(template    => 'family/index');
    $c->stash(layout      => 'default');

    my @members;
    foreach my $person (values %{ $c->app->gramps->people }) {
      my $name = $person->primary_name;
      if ($name) {
        my $sn = $name->primary_surname;
        if ( $sn
          && length($sn->display_name)
          && $sn->display_name eq $family_name) {
          $logger->debug(sprintf(
            'person %s with lastname %s matches %s',
            $person->id, $sn->display_name, $family_name
          ));
          push @members, $person;
        }
      }
    }
    $c->stash(members => \@members);

    my $family_tree = $c->_build_family_tree(\@members);
    $c->stash(family_tree => $family_tree);

    my $route = sprintf('/Harrypedia/people/%s', $family_name);
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

  sub _build_family_tree($self, $members) {
    my %member_lookup = map { $_->handle => $_ } @$members;
    my %processed;
    my @roots;

    # Find root ancestors (people with no parents in this family)
    foreach my $person (@$members) {
      next if $processed{ $person->handle };

      if ($self->_has_parents_in_family($person, \%member_lookup)) {
        next;    # Skip, will be added as child
      }

      # This is a root - build their subtree
      my $subtree =
        $self->_build_person_subtree($person, \%member_lookup, \%processed);
      push @roots, $subtree if $subtree;
    }

    # Sort roots by birth date
    @roots = sort {
      $self->app->gramps->compare_by_birth_date($a->{person}, $b->{person})
    } @roots;

    return \@roots;
  }

  sub _has_parents_in_family ($self, $person, $member_lookup) {
    foreach my $family_handle (@{ $person->child_of_refs }) {
      my $family = $self->app->gramps->families->{$family_handle};
      next unless $family;

      # Find this person's child_ref to check if they're a foster child
      my $person_child_ref;
      foreach my $child_ref (@{ $family->child_refs }) {
        if ($child_ref->{handle} eq $person->handle) {
          $person_child_ref = $child_ref;
          last;
        }
      }

      next unless $person_child_ref;    # Safety check

      # Check if this person is a foster child
      my $father_rel = $person_child_ref->{father_rel} // '';
      my $mother_rel = $person_child_ref->{mother_rel} // '';

      # If they're a foster child to both parents, skip this family
      next if ($father_rel eq 'Foster' && $mother_rel eq 'Foster');

      # Check if non-foster father is in our member list
      # that assignment test will return falsy if $family->father_ref is undefined
      # The parentheses around the assignment are important -
      # without them, the precedence would be wrong
      if ($father_rel ne 'Foster' && (my $father_ref = $family->father_ref)) {
        if (exists $member_lookup->{$father_ref}) {
          return 1;
        }
      }

      # Check if non-foster mother is in our member list
      if ($mother_rel ne 'Foster' && (my $mother_ref = $family->mother_ref)) {
        if (exists $member_lookup->{$mother_ref}) {
          return 1;
        }
      }
    }

    return 0;
  }

  sub _build_person_subtree($self, $person, $member_lookup, $processed) {
    return undef if $processed->{ $person->handle };
    $processed->{ $person->handle } = 1;

    my $node = {
      person   => $person,
      children => []
    };

    # Find children in this family
    my @children = $self->_get_children_in_family($person, $member_lookup);

    foreach my $child (@children) {
      next if $processed->{ $child->handle };

      my $child_node =
        $self->_build_person_subtree($child, $member_lookup, $processed);
      push @{ $node->{children} }, $child_node if $child_node;
    }

    # Sort children by birth date
    @{ $node->{children} } = sort {
      $self->app->gramps->compare_by_birth_date($a->{person}, $b->{person})
    } @{ $node->{children} };

    return $node;
  }

  sub _get_children_in_family($self, $person, $member_lookup) {
    my @children;

    # Look through families where this person is a parent
    foreach my $family_handle ($person->parent_in_refs->@*) {
      my $family = $self->app->gramps->families->{$family_handle};
      next unless $family;

      foreach my $child_ref ($family->child_refs->@*) {
        my $child_handle = $child_ref->{handle};
        my $child        = $member_lookup->{$child_handle};
        next unless $child;    # Child not in this family name

        push @children, $child;
      }
    }

    return @children;
  }

}
1;
__END__
