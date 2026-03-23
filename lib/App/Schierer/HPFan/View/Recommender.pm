package App::Schierer::HPFan::View::Recommender;
# cspell: disable

use v5.42.0;
use Mooish::Base -standard;

use Future::AsyncAwait;
use Future::Utils qw(fmap_void);
use IO::Async::Loop;
use IO::Async::Timer::Countdown;
use Net::Async::HTTP;
require Mojo::DOM58;
require URI;
use List::Util  qw(min any all);
use Time::HiRes ();
use MCE;
use MCE::Step;
use Sereal qw(encode_sereal decode_sereal);

# --- IO::Async plumbing ---

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

# --- Rate limiting ---
# Tracks when the next request slot opens.  Because the event loop is
# cooperative, the read-modify-write on _next_fetch_at is atomic -- no
# concurrent fmap_void task can interleave between the read and the write.

has _next_fetch_at => (is => 'rw', default => sub { 0 });

async sub _claim_rate_slot ($self) {
    my $now  = Time::HiRes::time();
    my $slot = $self->_next_fetch_at;
    $self->_next_fetch_at($slot + $self->rate_delay);

    my $wait = $slot - $now;
    return unless $wait > 0.001;

    my $f = $self->_loop->new_future;
    my $t = IO::Async::Timer::Countdown->new(
        delay     => $wait,
        on_expire => sub { $f->done },
    );
    $self->_loop->add($t);
    $t->start;
    await $f;
    $self->_loop->remove($t);
}

# --- Configuration ---

has rate_delay     => (is => 'ro', default => 1);
has max_concurrent => (is => 'ro', default => 2);
has parse_workers  => (is => 'ro', default => 4);
has max_retries    => (is => 'ro', default => 3);

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

# --- Callbacks ---

has on_progress => (
    is      => 'rw',
    default => sub { async sub { } },
);
has on_result => (
    is      => 'rw',
    default => sub { async sub { } },
);

# --- configure ---

sub configure ($self, %opts) {
    if (my $wait = $opts{wait_level}) {
        if ($wait eq 'very long') {
            $self->bkmrkr_limit(50); $self->kdsr_limit(20);
            $self->bkmrk_pages(10); $self->tag_page_limit(20);
        }
        elsif ($wait eq 'long') {
            $self->bkmrkr_limit(35); $self->kdsr_limit(15);
            $self->bkmrk_pages(4);  $self->tag_page_limit(10);
        }
        elsif ($wait eq 'medium') {
            $self->bkmrkr_limit(20); $self->kdsr_limit(10);
            $self->bkmrk_pages(2);  $self->tag_page_limit(5);
        }
        else {    # short
            $self->bkmrkr_limit(10); $self->kdsr_limit(5);
            $self->bkmrk_pages(1);  $self->tag_page_limit(3);
        }
    }

    $self->bkmrkr_limit(0 + $opts{bkmrkr_limit})    if $opts{bkmrkr_limit};
    $self->kdsr_limit(0 + $opts{kdsr_limit})         if $opts{kdsr_limit};
    $self->bkmrk_pages(0 + $opts{bkmrk_pages})      if $opts{bkmrk_pages};
    $self->tag_page_limit(0 + $opts{tag_page_limit}) if $opts{tag_page_limit};

    if (my $bl = $opts{blacklist}) {
        my @tags = map { s/^\s+|\s+$//gr } grep { length } split /,/, lc($bl);
        $self->blacklist_tags(\@tags);
    }

    if (my $en = $opts{enforce}) {
        my @tags = map { s/^\s+|\s+$//gr } grep { length } split /,/, lc($en);
        $self->enforce_tags(\@tags);
    }

    $self->soft_enforcement($opts{soft_enforcement} // 1);
}

# --- HTTP ---

# Returns HTML string on success, undef on permanent failure.
# Retries on 429 (respecting Retry-After) and 5xx up to max_retries times.
async sub _get ($self, $url) {
    my $uri = URI->new($url);

    for my $attempt (1 .. $self->max_retries + 1) {
        await $self->_claim_rate_slot;

        my $resp = eval { await $self->_ua->GET($uri) };
        if ($@ || !$resp) {
            my $err = $@ ? "$@" : 'no response';
            $err =~ s/\s+/ /g;
            push @{ $self->errors }, "Fetch error for $url (attempt $attempt): $err"
                if $attempt == $self->max_retries + 1;
            next if $attempt <= $self->max_retries;
            return undef;
        }

        my $code = $resp->code;

        return $resp->decoded_content if $code >= 200 && $code < 400;

        # Transient: rate-limited or server error -- wait and retry
        if ($code == 429 || $code >= 500) {
            my $wait = $resp->header('Retry-After') // (30 * $attempt);
            push @{ $self->errors },
                "HTTP $code from AO3 for $url (attempt $attempt), waiting ${wait}s";
            my $f = $self->_loop->new_future;
            my $t = IO::Async::Timer::Countdown->new(
                delay     => $wait,
                on_expire => sub { $f->done },
            );
            $self->_loop->add($t);
            $t->start;
            await $f;
            $self->_loop->remove($t);
            next;
        }

        # Permanent failure (404, 403, etc.)
        push @{ $self->errors }, "HTTP $code for $url";
        return undef;
    }

    return undef;
}

# --- Fetch phase (IO::Async, rate-limited, handles pagination) ---
# Returns a flat list of {html, source, page_url} hashrefs.

async sub _fetch_phase ($self, $items) {
    my @all_pages;

    await fmap_void(
        async sub ($item) {
            my @pages = await $self->_fetch_paginated(
                $item->{url}, $item->{source}, $item->{pages_left},
            );
            # push is safe here: cooperative scheduler can't interleave
            # between tasks except at explicit await points
            push @all_pages, @pages;
        },
        foreach    => $items,
        concurrent => $self->max_concurrent,
    );

    return @all_pages;
}

async sub _fetch_paginated ($self, $url, $source, $pages_left) {
    return () if $pages_left <= 0;

    my $html = await $self->_get($url);
    return () unless $html;

    my @pages = ({ html => $html, source => $source, page_url => $url });

    if ($pages_left > 1) {
        # Minimal parse: just find the next-page link, nothing more
        my $dom = Mojo::DOM58->new($html);
        if (my $next_a = $dom->at('a[rel="next"]')) {
            if (my $href = $next_a->{href}) {
                my $next_url = $href =~ m{^https?://}
                    ? $href
                    : 'https://archiveofourown.org' . $href;
                push @pages,
                    await $self->_fetch_paginated($next_url, $source, $pages_left - 1);
            }
        }
    }

    return @pages;
}

# --- Parse phase (MCE workers, CPU-bound HTML parsing) ---
# Workers are forked after all IO::Async fetches are complete, so the
# dormant event loop state in each worker process is harmless.

sub _parse_phase ($self, $pages) {
    return [] unless @$pages;

    my @raw = mce_step {
        task_name   => ['AO3Parser'],
        max_workers => [$self->parse_workers],
        chunk_size  => 1,
        freeze      => \&encode_sereal,
        thaw        => \&decode_sereal,
    }, \&_mce_parse_task, $pages;

    return [map { ref $_ eq 'ARRAY' ? @$_ : $_ } @raw];
}

# Module-level MCE task: receives [{html,source,page_url}], emits blurbs
sub _mce_parse_task ($mce, $chunk_ref, $chunk_id) {
    my @results;
    for my $page (@$chunk_ref) {
        push @results, _parse_html_page($page->{html}, $page->{source});
    }
    MCE->gather(\@results);
}

# Pure function: parse one fetched page, return list of blurb hashrefs
sub _parse_html_page ($html, $source) {
    my $dom    = Mojo::DOM58->new($html);
    my @blurbs;
    for my $el ($dom->find('li.bookmark.blurb, li.work.blurb')->each) {
        my $blurb = _parse_blurb_el($el, $source);
        push @blurbs, $blurb if $blurb;
    }
    return @blurbs;
}

# Pure function: extract structured data from one blurb element
sub _parse_blurb_el ($el, $source) {
    my $title_a = $el->at('h4.heading a[href*="/works/"]');
    return unless $title_a && $title_a->{href};

    my $work_url = 'https://archiveofourown.org' . $title_a->{href};
    my ($work_id) = $work_url =~ m{/works/(\d+)};
    return unless $work_id;

    my $title = $title_a->all_text;

    my @author_els = $el->find('h4.heading a[href*="/users/"]')->each;
    my $author     = @author_els
        ? join(', ', map { $_->all_text } @author_els)
        : 'Anonymous';
    my $author_url = @author_els
        ? 'https://archiveofourown.org' . $author_els[0]{href}
        : undef;

    my @tags     = map { lc $_->all_text } $el->find('a.tag')->each;
    my $tags_str = join(', ', @tags);

    my $word_count = do { my $e = $el->at('dd.words');    $e ? ($e->all_text =~ s/,//gr) : '' };
    my $hits       = do { my $e = $el->at('dd.hits');     $e ? ($e->all_text =~ s/,//gr) : '0' };
    my $kudos      = do { my $e = $el->at('dd.kudos');    $e ? ($e->all_text =~ s/,//gr) : '0' };
    my $chapters   = do { my $e = $el->at('dd.chapters'); $e ? $e->all_text : '?/?' };
    my $summary    = do { my $e = $el->at('blockquote.userstuff'); $e ? $e->all_text : '' };
    my $date       = do { my $e = $el->at('p.datetime');  $e ? $e->all_text : '' };

    return {
        id          => $work_id,
        url         => $work_url,
        title       => $title,
        author      => $author,
        author_url  => $author_url,
        tags        => $tags_str,
        summary     => $summary,
        word_count  => $word_count,
        chapters    => $chapters,
        update_date => $date,
        hits        => $hits,
        kudos       => $kudos,
        source      => $source,
    };
}

# --- Score and emit (main process, after MCE parse) ---

async sub _score_blurbs ($self, $blurbs) {
    for my $blurb (@$blurbs) {
        my $work_id  = $blurb->{id};
        my $source   = $blurb->{source};
        my $tags_str = $blurb->{tags};

        # Blacklist
        if (@{ $self->blacklist_tags }) {
            next if any { index($tags_str, $_) >= 0 } @{ $self->blacklist_tags };
        }

        # Hard enforce
        if (!$self->soft_enforcement && @{ $self->enforce_tags }) {
            next unless all { index($tags_str, $_) >= 0 } @{ $self->enforce_tags };
        }

        my $soft_enforced = 0;
        if ($self->soft_enforcement && @{ $self->enforce_tags }) {
            $soft_enforced =
                (all { index($tags_str, $_) >= 0 } @{ $self->enforce_tags }) ? 1 : 0;
        }

        my $is_new = !exists $self->results->{$work_id};
        my $rec    = $self->results->{$work_id} //= {
            id            => $work_id,
            url           => $blurb->{url},
            title         => $blurb->{title},
            author        => $blurb->{author},
            author_url    => $blurb->{author_url},
            tags          => $tags_str,
            summary       => $blurb->{summary},
            word_count    => $blurb->{word_count},
            chapters      => $blurb->{chapters},
            update_date   => $blurb->{update_date},
            hits          => $blurb->{hits},
            kudos         => $blurb->{kudos},
            bkmrkr_count  => 0,
            kdsr_count    => 0,
            tag_count     => 0,
            soft_enforced => 0,
        };

        if    ($source eq 'bookmarker') { $rec->{bkmrkr_count}++ }
        elsif ($source eq 'kudoser')    { $rec->{kdsr_count}++ }
        else                            { $rec->{tag_count}++ }

        $rec->{soft_enforced} ||= $soft_enforced;
        $rec->{score} =
              ($rec->{bkmrkr_count} * $self->bkmrkr_weight)
            + ($rec->{kdsr_count}   * $self->kdsr_weight)
            + ($rec->{tag_count}    * $self->tag_weight);
        $rec->{score} *= 2 if $rec->{soft_enforced};

        await $self->on_result->($rec, $is_new);
    }
}

# --- run ---

async sub run ($self, @urls) {
    $self->results({});
    $self->errors([]);
    $self->_next_fetch_at(0);

    # Phase 1: fetch and parse each input work inline (typically 1-3 URLs)
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

    # Build fetch-item lists for phases 2-4
    my (@bk_items, @kd_items, @tag_items);

    for my $work (@works) {
        my @bk_urls  = @{ $work->{bookmark_users} };
        my @kd_urls  = @{ $work->{kudos_users} };
        my @tag_urls = @{ $work->{tag_urls} };

        my $bk_limit  = min($self->bkmrkr_limit,   scalar @bk_urls);
        my $kd_limit  = min($self->kdsr_limit,      scalar @kd_urls);
        my $tag_limit = min($self->tag_page_limit,  scalar @tag_urls);

        push @bk_items, map {
            { url => $bk_urls[$_] . '/bookmarks', source => 'bookmarker',
              pages_left => $self->bkmrk_pages }
        } 0 .. $bk_limit - 1;

        push @kd_items, map {
            { url => $kd_urls[$_] . '/bookmarks', source => 'kudoser',
              pages_left => $self->bkmrk_pages }
        } 0 .. $kd_limit - 1;

        push @tag_items, map {
            my ($tag_name) = $tag_urls[$_] =~ m{/tags/([^/]+)};
            $tag_name ? {
                url    => 'https://archiveofourown.org/works?commit=Sort+and+Filter'
                        . '&work_search%5Bsort_column%5D=kudos_count'
                        . '&tag_id=' . $tag_name,
                source     => 'tag',
                pages_left => 1,
            } : ()
        } 0 .. $tag_limit - 1;
    }

    # Phase 2: bookmarker recs
    if (@bk_items) {
        await $self->on_progress->(
            sprintf("Fetching %d bookmarker page set(s)...", scalar @bk_items));
        my @pages = await $self->_fetch_phase(\@bk_items);
        await $self->on_progress->(
            sprintf("Parsing %d bookmarker page(s)...", scalar @pages));
        await $self->_score_blurbs($self->_parse_phase(\@pages));
    }

    # Phase 3: kudoser recs
    if (@kd_items) {
        await $self->on_progress->(
            sprintf("Fetching %d kudoser page set(s)...", scalar @kd_items));
        my @pages = await $self->_fetch_phase(\@kd_items);
        await $self->on_progress->(
            sprintf("Parsing %d kudoser page(s)...", scalar @pages));
        await $self->_score_blurbs($self->_parse_phase(\@pages));
    }

    # Phase 4: tag recs
    if (@tag_items) {
        await $self->on_progress->(
            sprintf("Fetching %d tag page(s)...", scalar @tag_items));
        my @pages = await $self->_fetch_phase(\@tag_items);
        await $self->on_progress->(
            sprintf("Parsing %d tag page(s)...", scalar @pages));
        await $self->_score_blurbs($self->_parse_phase(\@pages));
    }

    # Remove input works from results
    my %input_ids = map { $_->{id} => 1 } @works;
    delete $self->results->{$_} for keys %input_ids;

    return $self->_build_output;
}

# --- Input work parsing (async, inline -- not MCE-worthy for 1-3 URLs) ---

async sub _parse_input_work ($self, $url) {
    my $html = await $self->_get($url . '?view_adult=true');
    return undef unless $html;

    my $dom = Mojo::DOM58->new($html);

    my $summary_el = $dom->at('blockquote.userstuff');
    unless ($summary_el) {
        # Got a 200 but not a work page -- likely a login wall or challenge page
        my $page_title = $dom->at('title');
        my $hint = $page_title ? $page_title->all_text : 'unknown page';
        push @{ $self->errors }, "Unexpected response for $url (got: $hint)";
        return undef;
    }

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
        my $bk_dom = Mojo::DOM58->new($bk_html);
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

sub _build_output ($self) {
    my @recs;
    for my $rec (values %{ $self->results }) {
        $rec->{score} =
              ($rec->{bkmrkr_count} * $self->bkmrkr_weight)
            + ($rec->{kdsr_count}   * $self->kdsr_weight)
            + ($rec->{tag_count}    * $self->tag_weight);
        $rec->{score} *= 2 if $rec->{soft_enforced};
        push @recs, $rec;
    }
    return [sort { $b->{score} <=> $a->{score} } @recs];
}

1;
