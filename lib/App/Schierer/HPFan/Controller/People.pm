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
  use Log::Log4perl;
  require Data::Printer;
  use Carp;

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info("ControllerBase register function");

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

    $app->plugins->on(
      'gramps_initialized' => sub($c, $gramps) {
        $logger->debug('::Controller::People gramps_initialized sub start');

        foreach my $person (values %{ $gramps->people }) {
          my $name  = $person->primary_name();
          my $first = $name->first;
          my $last;
          foreach my $sn (@{ $name->surnames }) {
            if ($sn->prim) {
              $last = $sn;
              last;
            }
          }
          if (not defined $last && scalar @{ $name->surnames }) {
            $last = $name->surnames->[0];
          }
          my $route = sprintf('%s %s/%s %s',
            $last->prefix   ? $last->prefix   : '',
            $last->value    ? $last->value    : 'Unknown',
            $first        ? $first        : $person->id,
            $name->suffix ? $name->suffix : '',
          );
          $route =~ s/^\s+|\s+$//g;
          $route = '/Harrypedia/people/' . $route;
          my $rn    = $route =~ s/ /_/gr;

          my $title = $self->print_name($person);

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
    );
  }

  sub print_name ($self, $person) {
    my $name  = $person->primary_name();
    my $first = $name->first;
    my $last;
    foreach my $sn (@{ $name->surnames }) {
      if ($sn->prim) {
        $last = $sn;
        last;
      }
    }
    if (not defined $last && scalar @{ $name->surnames }) {
      $last = $name->surnames->[0];
    }
    my $printName = sprintf('%s %s %s %s',
      $first        ? $first        : 'Unknown',
      $last->prefix   ? $last->prefix   : '',
      $last->value    ? $last->value    : 'Unknown',
      $name->suffix ? $name->suffix : '',
    );
    $printName =~ s/^\s+|\s+$//g;
    return $printName;

  }

  sub person_details ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug("start of person_details method");
    my $id = $c->param('id');


    if ($id) {
      $logger->debug("person_details detects id $id");
      my $person = $c->app->person_by_id($id);
      if ($person) {
        $logger->debug("found person for id $id");



        $c->stash(person => $person);
        $c->stash(layout => 'default');
        $c->stash(template => 'person/details');
        $c->stash(printName => $c->print_name($person));

        return $c->render;
      }
    }
    return $c->reply->not_found;
  }

}
1;

__END__
