use v5.42;
use utf8::all;
use Test::More;
use experimental qw(class);
use utf8::all;
require Path::Tiny;
use Scalar::Util qw(blessed);

require App::Schierer::HPFan;
require App::Schierer::HPFan::Logger::Config;
use App::Schierer::HPFan::Model::Gramps::GrampsDate;
use App::Schierer::HPFan::Model::Gramps::DateHelper;

# set up logging
my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
my $log4perl_logger = $lc->init('testing');

my $H = App::Schierer::HPFan::Model::Gramps::DateHelper->new;

sub mk ($h) { $H->parse($h) }

sub is_date ($d, $name = 'is GrampsDate') {
  ok(blessed($d) && $d->isa('App::Schierer::HPFan::Model::Gramps::GrampsDate'),
    $name);
}

sub stringify ($d) {"$d"}    # relies on overload ""

# --- basic single-date comparisons
subtest 'single: cmp / eq' => sub {
  my $a = mk({ dateval => [1, 1, 1900, 0] });    # 1900-01-01
  my $b = mk({ dateval => [2, 1, 1900, 0] });    # 1900-01-02
  my $c = mk({ dateval => [0, 2, 1900, 0] });    # 1900-02 (no day)
  my $d = mk({ dateval => [0, 0, 1901, 0] });    # 1901 (year only)

  is_date $_ for ($a, $b, $c, $d);

  ok($a lt $b, '01 < 02');
  ok($a lt $c, '1900-01-* < 1900-02');
  ok($c lt $d, '1900-* < 1901');
  ok($b lt $d, '1900-01-02 < 1901');

  ok($a ne $b,                                 '!= works');
  ok($a eq mk({ dateval => [1, 1, 1900, 0] }), 'eq same');
  done_testing();

};

# --- modifiers on single dates shouldn’t change ordering anchor (only semantics)
subtest 'modifiers do not break ordering anchor' => sub {
  my $abt =
    mk({ dateval => [0, 0, 1900, 0], modifier => 3, text => 'about 1900' });
  my $bef =
    mk({ dateval => [0, 0, 1900, 0], modifier => 1, text => 'before 1900' });
  my $aft =
    mk({ dateval => [0, 0, 1900, 0], modifier => 2, text => 'after 1900' });

  # You decide exact anchors; these tests only enforce consistency:
  # - before < about < after (typical)
  ok($bef lt $abt, 'before 1900 < about 1900');
  ok($abt lt $aft, 'about 1900 < after 1900');

  like(stringify($abt), qr/\babout\b/i,  'string includes "about" once');
  like(stringify($bef), qr/\bbefore\b/i, 'string includes "before" once');
  like(stringify($aft), qr/\bafter\b/i,  'string includes "after" once');
  unlike(stringify($abt), qr/\babout\b.*\babout\b/i, 'no duplicate modifier');
  done_testing();

};

# --- ranges inside one dateval (indices 0..2 and 4..6)
subtest 'range-in-one-dateval' => sub {
  my $span = mk({
    dateval  => [9, 9, 1953, 0, 8, 9, 1954, 0],
    modifier => 4,                                     # between
    text     => 'between 1953-09-09 and 1954-09-08',
  });
  is_date $span;
  is($span->type, 'span', 'type=span for modifier=between');

  my $s = $span->start;
  my $e = $span->end;
  is_date $s, 'start is date';
  is_date $e, 'end is date';

  # Children should NOT carry parent modifier/quality in stringification
  unlike(
    stringify($s),
    qr/\bbetween|estimated|calculated\b/i,
    'start has no parent meta'
  );
  unlike(
    stringify($e),
    qr/\bbetween|estimated|calculated\b/i,
    'end has no parent meta'
  );

  like(stringify($span), qr/^between\b.*\band\b/i,
    'parent prints "between … and …" once');
  unlike(stringify($span), qr/\bbetween\b.*\bbetween\b/i,
    'no duplicated "between"');
  done_testing();

};

# --- explicit range shape
subtest 'explicit range {start,end}' => sub {
  my $rng = mk({
    type     => 'range',
    modifier => 5,                                 # from
    start    => { dateval => [1, 1, 1890, 0] },
    end      => { dateval => [0, 6, 1895, 0] },    # 1895-06
  });
  like(stringify($rng), qr/^from\s+1890-01-01\s+to\s+1895-06\b/i,
    'from … to …');

  # Open-ended from
  my $open = mk({
    dateval  => [15, 1, 1880, 0, 0, 0, 0, 0],      # only start present
    modifier => 5,
    text     => 'from 1880-01-15',
  });
  like(stringify($open), qr/^from\s+1880-01-15$/i,
    'open-ended "from" shows only start');
  done_testing();

};

# --- ordering with ranges
subtest 'ordering: single vs range' => sub {
  my $mid1890      = mk({ dateval => [1, 7, 1890, 0] });    # 1890-07-01
  my $rng1889_1890 = mk({
    dateval  => [1, 1, 1889, 0, 31, 12, 1890, 0],    # 1889-01-01 .. 1890-12-31
    modifier => 4,
  });
  my @sorted = sort { $a cmp $b } ($mid1890, $rng1889_1890);
  # Expected: range starts before the single-day, so it should come first
  is_deeply(
    [map stringify($_),        @sorted],
    [stringify($rng1889_1890), stringify($mid1890)],
    'range sorts before single it covers (by start)'
  );

  done_testing();

};

# --- transitivity & antisymmetry smoke checks (important for sort sanity)
subtest 'cmp: transitivity & antisymmetry (smoke)' => sub {
  my @ds = (
    mk({ dateval => [1, 1, 1890, 0] }),
    mk({ dateval => [0, 6, 1895, 0] }),
    mk({ dateval => [0, 0, 1900, 0] }),
  );
  my @sorted = sort { $a cmp $b } @ds;
  for my $i (0 .. $#sorted - 1) {
    ok($sorted[$i] le $sorted[$i + 1], 'non-decreasing');
  }
  # antisymmetry: if a <= b and b <= a then a eq b
  for my $i (0 .. $#sorted) {
    for my $j (0 .. $#sorted) {
      next unless ($sorted[$i] le $sorted[$j] && $sorted[$j] le $sorted[$i]);
      ok($sorted[$i] eq $sorted[$j], 'antisymmetry holds');
    }
  }
  done_testing();

};

# --- equality across different shapes that represent the same point
subtest 'eq across shapes' => sub {
  my $by_text = mk({ text    => '1900-01-01' });
  my $by_val  = mk({ dateval => [1, 1, 1900, 0] });
  ok($by_text eq $by_val, 'text and structured single are equal');

  my $yyyy     = mk({ dateval => [0, 0, 1900, 0] });
  my $yyyy_txt = mk({ text    => '1900' });
  ok($yyyy eq $yyyy_txt, 'year-only equality');
  done_testing();

};

done_testing();
