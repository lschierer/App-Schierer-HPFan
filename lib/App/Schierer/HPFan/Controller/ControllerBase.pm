use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojo::File;
require YAML::PP;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::ControllerBase {
  use Mojo::Base 'Mojolicious::Controller';
  use Mojo::Base 'Mojolicious::Plugin', -role, -signatures;
  use Log::Log4perl;
  use Carp;

  sub getBase ($self) {
    return "/" . __PACKAGE__;
  }

  my $logger;

  sub register($self, $app, $config //= {}) {
    $logger = $app->logger(__PACKAGE__);
    $logger->info(sprintf(
      'register function for %s with logging category %s.',
      __PACKAGE__, $logger->category()
    ));

    my $routes = $app->routes;

    $routes->get('/favicon.svg')->to(
      cb => sub ($c) {
        $c->reply->static('images/favicon.svg');
      }
    );

    my $gramps_export =
      $app->config('distDir')->child('share/data/gramps');
    my $gramps_db = $app->config('distDir')->child('grampsdb/sqlite.db');

    my $dist_dir = $self->config('distDir');
    my $db_file  = $dist_dir->child('grampsdb/sqlite.db');

    my $gramps = App::Schierer::HPFan::Model::Gramps->new(
      gramps_export => $gramps_export,
      gramps_db     => $gramps_db,
    );

    state $initialized = do {
      $logger->info("⚙️  Running gramps import...");
      $gramps->execute_import();
      $gramps->build_indexes();
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
        my $APP_START_TIME = $app->config->{'APP_START_TIME'};
        $c->render(
          json => {
            status              => 'ok',
            mode                => $app->mode // 'unknown',
            time                => scalar localtime,
            app_started_at      => scalar(localtime($APP_START_TIME)),
            app_uptime_seconds  => time() - $APP_START_TIME,
            build_time          => $app->config->{'version'}->{'build-time'},
            cdk_deployment_time =>
              $app->config->{'HPFAN-Environment'}->{'DEPLOYMENT_TIME'}
              // 'unknown',
            container_id => $app->config->{'HPFAN-Environment'}->{'HOSTNAME'}
              // 'unknown',    # ECS sets this automatically
            image_tag => $app->config->{'HPFAN-Environment'}->{'IMAGE_TAG'}
              // 'unknown',
            image_uri => $app->config->{'HPFAN-Environment'}->{'IMAGE_URI'}
              // 'unknown',
            version    => $app->VERSION,
            git_commit => $app->config->{'version'}->{'git-commit'},
          },
          status => 200
        );
      }
    );

  }

}
1;

__END__
