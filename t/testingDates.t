use v5.42.0;
use experimental qw(class);
use utf8::all;

require Date::Calc::Object;
use Date::Calc qw(Date_to_Days);
use App::Schierer::HPFan::Model::CustomDate;

use Test::More;

BEGIN { use_ok('Date::Calc') };

use_ok('App::Schierer::HPFan::Model::CustomDate');

my $cd = App::Schierer::HPFan::Model::CustomDate->new(text => '0001-01-01');
ok($cd->sortval == 1721426, "CustomDate 0001-01-01 (Gregorian)");

$cd = App::Schierer::HPFan::Model::CustomDate->new(
  text => { dateval => [1, 1, 1900, 0] }
);
ok($cd->sortval == 1721426, "CustomDate (hash constructor) 1900-01-01 (Gregorian)");

$cd = App::Schierer::HPFan::Model::CustomDate->new(
  text => { dateval => [0, 2, 1900, 0] }
);
ok($cd->sortval == 1721426, "CustomDate (hash constructor) 1900-02-00 (Gregorian)");

ok(parse('0001-01-01') == 1721426, "0001-01-01 (Gregorian)");
ok(parse('0001-01-01') == 1721426, "0001-01-01 (Gregorian)");
ok(parse('0890-09-01') == 2046370, "0890-09-01 (Gregorian)");
ok(parse('0955-11-23') == 2070193, "0955-11-23 (Gregorian)");
ok(parse('0959-10-01') == 2071601, "0001-01-01 (Gregorian)");
ok(parse('1729-05-28') == 2352712, "0001-01-01 (Gregorian)");

done_testing();

sub parse($string) {
  if($string =~ /(\d{4})-(\d{2})-(\d{2})/){
    my ($year, $month, $day) = ($1, $2, $3);
    print "found $year $month $day from $string\n";
    my $dc = Date::Calc->new([$year, $month, $day]);
    return gregorian_to_jdn($dc->date());
  }
  return 0 ;
}

sub gregorian_to_jdn ($y,$m,$d) {
    my $rd  = Date_to_Days($y,$m,$d); # Rata Die
    my $jdn = $rd + 1721425;
    print "jdn is $jdn\n";
    return $jdn;
}
