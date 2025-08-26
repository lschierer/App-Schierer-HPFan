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
use List::Util qw(uniq);
BEGIN { use_ok('App::Schierer::HPFan::Model::Gramps') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $lc = App::Schierer::HPFan::Logger::Config->new('App-Schierer-HPFan');
my $log4perl_logger = $lc->init('testing');

my $gramps_file = './share/data/gramps';
my $gramps_db = './share/grampsdb/sqlite.db';

my $gramps = App::Schierer::HPFan::Model::Gramps->new(
  gramps_export => $gramps_file,
  gramps_db     => $gramps_db,
);

$gramps->execute_import;
$gramps->build_indexes();

my $people        = $gramps->people;
my $events        = $gramps->events;
my $people_by_ev  = $gramps->people_by_event;  # { event_handle => [ Person, ... ] }
my $people_by_tag = $gramps->people_by_tag;    # { tag_handle   => [ Person, ... ] }

my @unknown_events =
  grep { !exists $gramps->events->{$_} } keys %{ $gramps->people_by_event };
is_deeply(\@unknown_events, [], 'All people_by_event keys exist in events');

# 2) tag handles referenced by people but not present in tags
my @unknown_tags =
  grep { !exists $gramps->tags->{$_} } keys %{ $gramps->people_by_tag };
is_deeply(\@unknown_tags, [], 'All people_by_tag keys exist in tags');

my $pbtk_count = scalar keys %{ $gramps->people_by_tag };
my $gtk_count = scalar keys %{ $gramps->tags };
my @pbtk = sort keys %{ $gramps->people_by_tag };
my @gtk = sort keys %{ $gramps->tags };
if( $pbtk_count != $gtk_count ){
  say "keys of people by tag: " . Data::Printer::np(@pbtk);
  say "keys of gramps tags: " . Data::Printer::np(@gtk);
}

# ---------- Build “truth” sets by walking people ----------
# ---------- Build “truth” sets by walking people (object-aware) ----------
my (%truth_by_event, %truth_by_tag); # { handle => { person_handle => 1 } }

for my $p (values %{ $gramps->people }) {
  my $ph = $p->handle // next;

  # event refs can be objects (Event::Reference) or bare handles
  my %seen_e;
  for my $eref (@{ $p->event_ref_list // [] }) {
    my $eh =
      (ref($eref) && $eref->can('ref')) ? ($eref->ref // '') :
      ref($eref) eq 'HASH'              ? ($eref->{ref} // '') :
                                          "$eref";
    next unless length $eh;
    next if $seen_e{$eh}++;
    $truth_by_event{$eh}{$ph} = 1;
  }

  ## tag refs may be objects, hashes, or strings; normalize the same way
  my %seen_t;
  for my $tref (@{ $p->tag_list // [] }) {
    my $th = ref($tref) eq 'HASH' ? ($tref->{ref} // '') :
                                  "$tref";
    next unless length $th;
    next if $seen_t{$th}++;
    $truth_by_tag{$th}{$ph} = 1;
  }
}
ok(scalar keys %truth_by_tag == scalar keys %{$gramps->tags}, 'truth_by_tag has the same number of keys as there are tags.');
ok(scalar keys %truth_by_tag == scalar keys %{$gramps->people_by_tag}, 'truth_by_tag has the same number of keys as there are tag index entries.');
ok(scalar keys %{$gramps->people_by_tag} == scalar keys %{$gramps->tags}, 'there are the same number of tags as tag index entries');

# ---------- Compare keys (which events/tags have participants) ----------
sub sorted_keys { [ sort keys %{+shift} ] }

is_deeply(
  sorted_keys(\%{$people_by_ev}),
  sorted_keys(\%truth_by_event),
  'people_by_event keys match ground truth (events with participants)'
);

#is_deeply(
#  sorted_keys(\%{$people_by_tag}),
#  sorted_keys(\%truth_by_tag),
#  'people_by_tag keys match ground truth (tags with participants)'
#);

# ---------- Compare contents per key ----------
sub persons_to_set {
  my ($ary) = @_;
  my %set;
  for my $obj (@{ $ary // [] }) {
    my $h = $obj && $obj->can('handle') ? $obj->handle : undef;
    $set{$h} = 1 if defined $h;
  }
  \%set
}

sub set_eq {
  my ($a, $b) = @_;
  return 0 unless defined $a && defined $b;
  return 0 unless keys(%$a) == keys(%$b);
  for my $k (keys %$a) { return 0 unless $b->{$k} }
  return 1;
}

# events
for my $eh (keys %truth_by_event) {
  my $have = persons_to_set($people_by_ev->{$eh});
  my $want = $truth_by_event{$eh};
  ok(set_eq($have, $want), "people_by_event{$eh} matches participants");
  unless (set_eq($have, $want)) {
    diag "Expected: @{[ sort keys %$want ]}";
    diag "Got:      @{[ sort keys %$have ]}";
  }
}

## tags
#for my $th (keys %truth_by_tag) {
#  my $have = persons_to_set($people_by_tag->{$th});
#  my $want = $truth_by_tag{$th};
#  ok(set_eq($have, $want), "people_by_tag{$th} matches participants");
#  unless (set_eq($have, $want)) {
#    diag "Expected: @{[ sort keys %$want ]}";
#    diag "Got:      @{[ sort keys %$have ]}";
#  }
#}

# ---------- Optional: sanity checks ----------
# 1) No dupes stored in the arrays (protect against accidental push dupes)
for my $eh (keys %$people_by_ev) {
  my @handles = map { $_->handle } @{ $people_by_ev->{$eh} // [] };
  is_deeply(\@handles, [ uniq @handles ], "No duplicate persons in people_by_event{$eh}");
}
#for my $th (keys %$people_by_tag) {
#  my @handles = map { $_->handle } @{ $people_by_tag->{$th} // [] };
#  is_deeply(\@handles, [ uniq @handles ], "No duplicate persons in people_by_tag{$th}");
#}

# 2) If you expect every referenced event handle to exist in $events, assert that:
for my $eh (keys %truth_by_event) {
  ok(exists $events->{$eh}, "Referenced event handle exists: $eh");
}

done_testing();

# Count elements in the XML file
sub count_xml_elements($file, $element) {
    my $content = Path::Tiny::path($file)->slurp_utf8;
    my @matches = $content =~ /<$element\s/g;
    return scalar @matches;
}
