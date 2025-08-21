use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;

require App::Schierer::HPFan;
require App::Schierer::HPFan::Logger::Config;
require App::Schierer::HPFan::Model::Gramps;
require App::Schierer::HPFan::Model::History::Event;
require App::Schierer::HPFan::Model::History::Gramps;
require App::Schierer::HPFan::View::Timeline;

use Test::More;
use List::Util qw(uniq);
BEGIN { use_ok('App::Schierer::HPFan::Model::Gramps') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
my $log4perl_logger = $lc->init('testing');

my $gramps_file = './share/potter_universe.gramps';
my $gramps_db = './share/grampsdb/sqlite.db';

my $gramps = App::Schierer::HPFan::Model::Gramps->new(
  gramps_export => $gramps_file,
  gramps_db     => $gramps_db,
);

$gramps->execute_import;
$gramps->build_indexes();

my $ge = App::Schierer::HPFan::Model::History::Gramps->new(
  gramps => $gramps
);
$ge->process();

#my $timeline_view = App::Schierer::HPFan::View::Timeline->new(
#  events => $ge->events,
#);
#my $svg = $timeline_view->create();
#say "svg size: " . length($svg);

done_testing();
