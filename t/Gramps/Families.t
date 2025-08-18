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

use Test::More;
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

$gramps->_import_families;

my $expected_families = count_xml_elements($gramps_file, 'family');

is(scalar keys %{$gramps->families}, $expected_families,
  "Imported $expected_families families");
ok(scalar keys %{$gramps->families} > 0, "Familes were imported");

done_testing();

# Count elements in the XML file
sub count_xml_elements($file, $element) {
    my $content = Path::Tiny::path($file)->slurp_utf8;
    my @matches = $content =~ /<$element\s/g;
    return scalar @matches;
}
