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

my $gramps = App::Schierer::HPFan::Model::Gramps->new(
  gramps_export => $gramps_file
);

$gramps->import_from_xml;

my $expected_tags = count_xml_elements($gramps_file, 'tag');
my $expected_events = count_xml_elements($gramps_file, 'event');
my $expected_people = count_xml_elements($gramps_file, 'person');
my $expected_families = count_xml_elements($gramps_file, 'family');

# Test that we imported the right number of each
is(scalar keys %{$gramps->tags}, $expected_tags,
   "Imported $expected_tags tags");
is(scalar keys %{$gramps->events}, $expected_events,
   "Imported $expected_events events");
is(scalar keys %{$gramps->people}, $expected_people,
   "Imported $expected_people people");
is(scalar keys %{$gramps->families}, $expected_families,
  "Imported $expected_families families");

# Also test that we have some data (in case the file is empty)
ok(scalar keys %{$gramps->tags} > 0, "Tags were imported");
ok(scalar keys %{$gramps->events} > 0, "Events were imported");
ok(scalar keys %{$gramps->people} > 0, "People were imported");
ok(scalar keys %{$gramps->families} > 0, "Familes were imported");


done_testing();

# Count elements in the XML file
sub count_xml_elements($file, $element) {
    my $content = Path::Tiny::path($file)->slurp_utf8;
    my @matches = $content =~ /<$element\s/g;
    return scalar @matches;
}
