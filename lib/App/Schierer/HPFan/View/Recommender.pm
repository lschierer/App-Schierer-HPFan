package App::Schierer::HPFan::View::Recommender;
# cspell: disable

use v5.42.0;
use Mooish::Base -standard;

use Future::AsyncAwait;
use IO::Async::Loop;
use IO::Async::Timer::Countdown;
use Net::Async::HTTP;
require Mojo::DOM58;
require URI;
use List::Util qw(min any all);

has _loop => (
  is      => 'ro',
  default => sub { IO::Async::Loop->new },
);

has _ua => (is => 'lazy');

sub _build__ua ($self) {
  my $ua = Net::Async::HTTP->new(
    user_agent               => 'Mozilla/5.0 (compatible; HPFanRec/1.0)',
    timeout                  => 30,
    max_redirects            => 5,
    max_connections_per_host => 1,
    pipeline                 => 0,
    stall_timeout            => 30,
  );
  $self->_loop->add($ua);
  return $ua;
}

has rate_delay => (is => 'ro', default => 1);

# --- Configuration ---

has bkmrkr_limit     => (is => 'rw', default => 35);
has kdsr_limit       => (is => 'rw', default => 15);
has bkmrk_pages      => (is => 'rw', default => 4);
has tag_page_limit   => (is => 'rw', default => 10);
has blacklist_tags   => (is => 'rw', default => sub { [] });
has enforce_tags     => (is => 'rw', default => sub { [] });
has soft_enforcement => (is => 'rw', default => 1);

# --- Scoring weights ---

has bkmrkr_weight => (is => 'ro', default => 21);
has kdsr_weight   => (is => 'ro', default => 10);
has tag_weight    => (is => 'ro', default => 5);

# --- State ---

has results => (is => 'rw', default => sub { {} });
has errors  => (is => 'rw', default => sub { [] });

# --- Callbacks (async-safe) ---

has on_progress => (
  is      => 'rw',
  default => sub {
    async sub { }
  }
);
has on_result => (
  is      => 'rw',
  default => sub {
    async sub { }
  }
);

sub configure ($self, %opts) {
  if (my $wait = $opts{wait_level}) {
    if ($wait eq 'very long') {
      $self->bkmrkr_limit(50);
      $self->kdsr_limit(20);
      $self->bkmrk_pages(10);
    }
    elsif ($wait eq 'long') {
      $self->bkmrkr_limit(35);
      $self->kdsr_limit(15);
      $self->bkmrk_pages(4);
    }
    else {
      $self->bkmrkr_limit(20);
      $self->kdsr_limit(10);
      $self->bkmrk_pages(2);
    }
  }

  if (my $bl = $opts{blacklist}) {
    my @tags = map {s/^\s+|\s+$//gr} grep {length} split /,/, lc($bl);
    $self->blacklist_tags(\@tags);
  }

  if (my $en = $opts{enforce}) {
    my @tags = map {s/^\s+|\s+$//gr} grep {length} split /,/, lc($en);
    $self->enforce_tags(\@tags);
  }

  $self->soft_enforcement($opts{soft_enforcement} // 1);
}

# --- Async HTTP ---

async sub _delay ($self) {
  my $f = $self->_loop->new_future;
  my $t = IO::Async::Timer::Countdown->new(
    delay     => $self->rate_delay,
    on_expire => sub { $f->done },
  );
  $self->_loop->add($t);
  $t->start;
  await $f;
  $self->_loop->remove($t);
}

async sub _get ($self, $url) {
  await $self->_delay;
  my $uri  = URI->new($url);
  my $resp = eval { await $self->_ua->GET($uri) };
  if ($@ || !$resp) {
    return undef;
  }
  return $resp->code >= 200 && $resp->code < 400
    ? $resp->decoded_content
    : undef;
}

sub _dom ($self, $html) {
  return Mojo::DOM58->new($html);
}

# --- Core logic ---

async sub run ($self, @urls) {
  $self->results({});
  $self->errors([]);

  # Phase 1: parse input works
  my @works;
  for my $url (@urls) {
    $url =~ s{/\z}{};
    await $self->on_progress->("Fetching input work: $url");
    my $work = await $self->_parse_input_work($url);
    if ($work) {
      push @works, $work;
    }
    else {
      push @{ $self->errors },
        "Could not parse work at $url - it may require login or be unavailable";
    }
  }

  return $self->_build_output unless @works;

  # Phase 2: bookmarker recs
  for my $work (@works) {
    my @bk_urls = @{ $work->{bookmark_users} };
    my $limit   = min($self->bkmrkr_limit, scalar @bk_urls);
    for my $i (0 .. $limit - 1) {
      await $self->on_progress->(
        sprintf("Bookmarker recs %d/%d", $i + 1, $limit));
      await $self->_add_bookmark_recs($bk_urls[$i] . '/bookmarks',
        $self->bkmrk_pages, 'bookmarker',);
    }
  }

  # Phase 3: kudoser recs
  for my $work (@works) {
    my @kd_urls = @{ $work->{kudos_users} };
    my $limit   = min($self->kdsr_limit, scalar @kd_urls);
    for my $i (0 .. $limit - 1) {
      await $self->on_progress->(sprintf("Kudoser recs %d/%d", $i + 1, $limit));
      await $self->_add_bookmark_recs($kd_urls[$i] . '/bookmarks',
        $self->bkmrk_pages, 'kudoser',);
    }
  }

  # Phase 4: tag recs
  for my $work (@works) {
    my @tag_urls = @{ $work->{tag_urls} };
    my $limit    = min($self->tag_page_limit, scalar @tag_urls);
    for my $i (0 .. $limit - 1) {
      await $self->on_progress->(sprintf("Tag recs %d/%d", $i + 1, $limit));
      await $self->_add_tag_recs($tag_urls[$i]);
    }
  }

  # Remove input works from results
  my %input_ids = map { $_->{id} => 1 } @works;
  delete $self->results->{$_} for keys %input_ids;

  return $self->_build_output;
}

async sub _parse_input_work ($self, $url) {
  my $html = await $self->_get($url . '?view_adult=true');
  return undef unless $html;

  my $dom = $self->_dom($html);

  my $summary_el = $dom->at('blockquote.userstuff');
  return undef unless $summary_el;    # restricted or invalid

  my $summary = $summary_el->all_text;

  my @tag_els  = $dom->find('a.tag')->each;
  my @tag_urls = map { 'https://archiveofourown.org' . $_->{href} }
    grep { $_->{href} && $_->{href} =~ m{^/tags/} } @tag_els;

  my @kudos_urls;
  my $kudos_p = $dom->at('p.kudos');
  if ($kudos_p) {
    @kudos_urls = map { 'https://archiveofourown.org' . $_->{href} }
      $kudos_p->find('a[href^="/users/"]')->each;
  }

  my $bk_html = await $self->_get($url . '/bookmarks');
  my @bk_urls;
  if ($bk_html) {
    my $bk_dom = $self->_dom($bk_html);
    @bk_urls = map { 'https://archiveofourown.org' . $_->{href} }
      $bk_dom->find('h5.byline a[href^="/users/"]')->each;
  }

  # Dedupe kudos vs bookmarkers
  my %bk_base = map { (m{(/users/[^/]+)})[0] => 1 } @bk_urls;
  @kudos_urls = grep {
    my ($base) = m{(/users/[^/]+)};
    $base && !$bk_base{$base};
  } @kudos_urls;

  my ($id) = $url =~ m{/works/(\d+)};

  return {
    id             => $id,
    url            => $url,
    summary        => $summary,
    tag_urls       => \@tag_urls,
    kudos_users    => \@kudos_urls,
    bookmark_users => \@bk_urls,
  };
}

async sub _add_bookmark_recs ($self, $url, $pages_left, $source) {
  return if $pages_left <= 0;

  my $html = await $self->_get($url);
  return unless $html;

  my $dom = $self->_dom($html);

  for my $blurb ($dom->find('li.bookmark.blurb')->each) {
    eval { $self->_parse_blurb($blurb, $source) };
    push @{ $self->errors }, "Error parsing bookmark blurb: $@" if $@;
  }

  # Follow pagination
  my $next_a = $dom->at('a[rel="next"]');
  if ($next_a && $next_a->{href}) {
    await $self->_add_bookmark_recs(
      'https://archiveofourown.org' . $next_a->{href},
      $pages_left - 1, $source,);
  }
}

async sub _add_tag_recs ($self, $tag_url) {
  my ($tag_name) = $tag_url =~ m{/tags/([^/]+)};
  return unless $tag_name;

  my $search_url =
      'https://archiveofourown.org/works?commit=Sort+and+Filter'
    . '&work_search%5Bsort_column%5D=kudos_count'
    . '&tag_id='
    . $tag_name;

  my $html = await $self->_get($search_url);
  return unless $html;

  my $dom = $self->_dom($html);

  for my $blurb ($dom->find('li.work.blurb')->each) {
    eval { $self->_parse_blurb($blurb, 'tag') };
    push @{ $self->errors }, "Error parsing tag blurb: $@" if $@;
  }
}

# Shared blurb parser - works for both bookmark and tag listing blurbs
sub _parse_blurb ($self, $blurb, $source) {
  my $heading_a = $blurb->at('h4.heading a');
  return unless $heading_a && $heading_a->{href};

  my $work_url = 'https://archiveofourown.org' . $heading_a->{href};
  my ($work_id) = $work_url =~ m{/works/(\d+)};
  return unless $work_id;

  my $title    = $heading_a->all_text;
  my @tags     = map { lc $_->all_text } $blurb->find('a.tag')->each;
  my $tags_str = join(', ', @tags);

  # Blacklist
  if (@{ $self->blacklist_tags }) {
    return if any { index($tags_str, $_) >= 0 } @{ $self->blacklist_tags };
  }

  # Hard enforce
  if (!$self->soft_enforcement && @{ $self->enforce_tags }) {
    return unless all { index($tags_str, $_) >= 0 } @{ $self->enforce_tags };
  }

  my $wc_el      = $blurb->at('dd.words');
  my $word_count = $wc_el ? $wc_el->all_text : '';
  $word_count =~ s/,//g;

  my $hits_el = $blurb->at('dd.hits');
  my $hits    = $hits_el ? $hits_el->all_text : '0';
  $hits =~ s/,//g;

  my $kudos_el = $blurb->at('dd.kudos');
  my $kudos    = $kudos_el ? $kudos_el->all_text : '0';
  $kudos =~ s/,//g;

  my $ch_el    = $blurb->at('dd.chapters');
  my $chapters = $ch_el ? $ch_el->all_text : '?/?';

  my $sum_el  = $blurb->at('blockquote.userstuff');
  my $summary = $sum_el ? $sum_el->all_text : '';

  my $date_el = $blurb->at('p.datetime');
  my $date    = $date_el ? $date_el->all_text : '';

  my $soft_enforced = 0;
  if ($self->soft_enforcement && @{ $self->enforce_tags }) {
    $soft_enforced =
      (all { index($tags_str, $_) >= 0 } @{ $self->enforce_tags }) ? 1 : 0;
  }

  my $is_new = !exists $self->results->{$work_id};
  my $rec    = $self->results->{$work_id} //= {
    id            => $work_id,
    url           => $work_url,
    title         => $title,
    tags          => $tags_str,
    summary       => $summary,
    word_count    => $word_count,
    chapters      => $chapters,
    update_date   => $date,
    hits          => $hits,
    kudos         => $kudos,
    bkmrkr_count  => 0,
    kdsr_count    => 0,
    tag_count     => 0,
    soft_enforced => $soft_enforced,
  };

  if    ($source eq 'bookmarker') { $rec->{bkmrkr_count}++ }
  elsif ($source eq 'kudoser')    { $rec->{kdsr_count}++ }
  else                            { $rec->{tag_count}++ }

  $rec->{soft_enforced} ||= $soft_enforced;

  # Keep score current for streaming
  $rec->{score} =
      ($rec->{bkmrkr_count} * $self->bkmrkr_weight)
    + ($rec->{kdsr_count}   * $self->kdsr_weight)
    + ($rec->{tag_count}    * $self->tag_weight);
  $rec->{score} *= 2 if $rec->{soft_enforced};

  # Notify caller of new/updated result
  $self->on_result->($rec, $is_new);
}

sub _build_output ($self) {
  my @recs;
  for my $rec (values %{ $self->results }) {
    $rec->{score} =
      ($rec->{bkmrkr_count} * $self->bkmrkr_weight) +
      ($rec->{kdsr_count} * $self->kdsr_weight) +
      ($rec->{tag_count} * $self->tag_weight);

    $rec->{score} *= 2 if $rec->{soft_enforced};
    push @recs, $rec;
  }

  return [sort { $b->{score} <=> $a->{score} } @recs];
}

1;
