# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl App-Schierer-HPFan.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;

require App::Schierer::HPFan;
require App::Schierer::HPFan::Logger::Config;
require App::Schierer::HPFan::Model::Gramps;
require Log::Log4perl;

use Test::More;
use DBI;
use DBD::SQLite::Constants qw/:dbd_sqlite_string_mode/;

BEGIN { use_ok('App::Schierer::HPFan::Model::Gramps') }

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
my $log4perl_logger = $lc->init('testing');
my $logger = Log::Log4perl->get_logger('Test');

my $gramps_file = './share/potter_universe.gramps';
my $gramps_db   = './share/grampsdb/sqlite.db';

my $gramps = App::Schierer::HPFan::Model::Gramps->new(
  gramps_export => $gramps_file,
  gramps_db     => $gramps_db,
);

my $no_date_events = events_with_no_date();

$gramps->execute_import;
$gramps->_import_events;

my $expected_events = count_xml_elements($gramps_file, 'event');

is(scalar keys %{ $gramps->events },
  $expected_events, "Imported $expected_events events");
ok(scalar keys %{ $gramps->events } > 0, "Events were imported");

my @eventKeys = keys %{ $gramps->events };

for my $index (0 .. $#eventKeys) {
  subtest sprintf('detailed testing for Event number: %s', $index) => sub {
    my $key   = $eventKeys[$index];
    my $event = $gramps->events->{$key};
    $logger->info(sprintf('subtest for event %s %s', $key, $event->gramps_id));

    isa_ok(
      $event,
      'App::Schierer::HPFan::Model::Gramps::Event',
      sprintf('object test for index %s', $index)
    );

    my $date = $event->date;
    if ($date) {
      isa_ok(
        $date,
        'App::Schierer::HPFan::Model::Gramps::GrampsDate',
        sprintf('event date for %s', $event->gramps_id)
      );
      my $dmDate = $date->as_dm_date;
      if ($no_date_events->{ $event->gramps_id }) {
        # DB says "no date" — we should NOT get a parseable DM date
        ok(!defined($dmDate),
          sprintf('no DM date (as expected) for %s', $event->gramps_id));
        pass(sprintf 'Event %s has no date (acceptable)', $event->gramps_id);
      }
      else {
        ok(defined($dmDate),
          sprintf('as_dm_date returns something %s', $event->gramps_id));
        if ($dmDate) {
          isa_ok($dmDate, 'Date::Manip::Date',
            sprintf('Date::Manip::Date for %s', $event->gramps_id));
        }
        my $s = $date->to_string // '';
        ok(
          length($s) > 0,
          sprintf 'GrampsDate for %s prints something',
          $event->gramps_id
        );
      }
    }
    else {
      pass(sprintf 'Event %s has no date (acceptable)', $event->gramps_id);
    }

    done_testing();
  };
}

done_testing();

# Count elements in the XML file
sub count_xml_elements($file, $element) {
  my $content = Path::Tiny::path($file)->slurp_utf8;
  my @matches = $content =~ /<$element\s/g;
  return scalar @matches;
}

sub events_with_no_date {
  my %no_date = do {
    my $dbh = DBI->connect(
      "dbi:SQLite:$gramps_db",
      undef, undef,
      {
        RaiseError => 1,
        AutoCommit => 1,    #fallback just in case
      }
    );
    $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK;
    # One-time-ish setup (safe if repeated)
    $dbh->do('PRAGMA journal_mode=WAL');      # persistent per DB
    $dbh->do('PRAGMA synchronous=NORMAL');    # performance tradeoff ok for dev
    $dbh->do('PRAGMA temp_store=MEMORY');

    # "No date" = sortval 0 OR all dateval parts are 0 (day,month,year)
    my $sql = q{
      SELECT gramps_id
      FROM event
      WHERE COALESCE(json_extract(json_data,'$.date.sortval'),0) = 0
        OR (
              COALESCE(json_extract(json_data,'$.date.dateval[2]'),0) = 0 AND
              COALESCE(json_extract(json_data,'$.date.dateval[1]'),0) = 0 AND
              COALESCE(json_extract(json_data,'$.date.dateval[0]'),0) = 0
            )
    };

    my $ids = $dbh->selectcol_arrayref($sql) // [];
    $dbh->disconnect;
    map { $_ => 1 } @$ids;
  };
  return \%no_date;
}
