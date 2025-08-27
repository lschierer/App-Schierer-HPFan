use v5.42.0;
use experimental qw(class);
use utf8::all;
require Path::Tiny;

require App::Schierer::HPFan;
require App::Schierer::HPFan::Logger::Config;
require App::Schierer::HPFan::Model::Gramps;

use Test::More;
BEGIN { use_ok('App::Schierer::HPFan::Model::Gramps') }

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
my $log4perl_logger = $lc->init('testing');
my $logger = Log::Log4perl->get_logger('Test');


use_ok('App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type');

use_ok('App::Schierer::HPFan::Model::Gramps::Person::Child::Reference');

my $crt = App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type->new(
  value => 1
);

my $cr = App::Schierer::HPFan::Model::Gramps::Person::Child::Reference->new(
  data => {
    ref     => 'asdfasdfasdf',
    frel    => { value => 1 },
    mrel    => { value => 1 },
    private => 0,
  }
);

isa_ok($crt, 'App::Schierer::HPFan::Model::Gramps::Person::Child::Reference::Type');

is(defined($cr), 1, 'child reference defined');

$logger->debug("cr is $cr");

done_testing();
