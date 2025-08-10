use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::ControllerBase {
  use Mojo::Base 'Mojolicious::Controller';
  use Mojo::Base 'Mojolicious::Plugin', -role, -signatures;
  use Log::Log4perl;
  require Mojo::File;
  require YAML::PP;
  require Data::Printer;
  use Carp;

  sub getBase ($self) {
    return "/" . __PACKAGE__;
  }

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info("ControllerBase register function");

    $app->helper(logger => sub { return $logger });

    my $routes = $app->routes;

    $routes->get('/favicon.svg')->to(
      cb => sub ($c) {
        $c->reply->static('images/favicon.svg');
      }
    );

    my $gramps_export =
      $app->config('distDir')->child('potter_universe.gramps');
    my $gramps =
      App::Schierer::HPFan::Model::Gramps->new(gramps_export => $gramps_export,
      );

    state $initialized = do {
      $logger->info("⚙️  Running gramps import...");
      $gramps->import_from_xml();
      $logger->info("✅ gramps import completed.");

      $app->helper(gramps => sub { return $gramps });

      $app->helper(
        person_house => sub ($c, $person) {
          my %by_handle =
            %{ $gramps->tags };    # handle => Tag (assumes ->name or similar)

          for my $th (@{ $person->tag_refs // [] }) {
            my $tag  = $by_handle{$th} or next;
            my $name = $tag->name // '';
            $name =~ s/^\s+|\s+$//g;

            # exact house names
            return $name
              if $name =~ /^(?:Gryffindor|Hufflepuff|Ravenclaw|Slytherin)$/;

            # "House: Gryffindor" etc.
            if ($name =~
              /^House:\s*(Gryffindor|Hufflepuff|Ravenclaw|Slytherin)\b/i) {
              return ucfirst lc $1;
            }
          }

          return 'Unknown House';
        }
      );

      $app->helper(
        person_blood_status => sub ($c, $person) {
          my %by_handle =
            %{ $gramps->tags };    # handle => Tag (assumes ->name or similar)

          for my $th (@{ $person->tag_refs // [] }) {
            my $tag  = $by_handle{$th} or next;
            my $name = $tag->name // '';
            $name =~ s/^\s+|\s+$//g;

            # exact house names
            return $name
              if $name =~
              /^(?:pure-blood|half-blood|1st gen magical|hag|non-magical)$/;
          }

          return 'Unknown Status';
        }
      );

      $app->helper(
        person_economic_status => sub ($c, $person) {
          my %by_handle =
            %{ $gramps->tags };    # handle => Tag (assumes ->name or similar)

          for my $th (@{ $person->tag_refs // [] }) {
            my $tag  = $by_handle{$th} or next;
            my $name = $tag->name // '';
            $name =~ s/^\s+|\s+$//g;

            # exact house names
            return $name
              if $name =~ /^(?:Lower Class|Upper Class|Middle Class)$/;
          }

          return 'Unknown';
        }
      );

      $app->plugins->emit(gramps_initialized => $gramps);
      $app->config(gramps_initialized => 1);
      1;
    };

    $routes->get('/health')->to(
      cb => sub($c) {
        $c->render(
          json => {
            status  => 'ok',
            mode    => $app->mode // 'unknown',
            version => $app->VERSION,
            time    => scalar localtime,
          },
          status => 200
        );
      }
    );

  }

}
1;

__END__
