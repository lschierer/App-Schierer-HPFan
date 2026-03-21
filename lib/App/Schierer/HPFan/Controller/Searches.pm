package App::Schierer::HPFan::Controller::Searches;
# cspell: disable

use v5.42.0;
use Mooish::Base -standard;
extends 'WebFramework::Controller::Base';

use Future::AsyncAwait;
require App::Schierer::HPFan::View::Recommender;
require Path::Tiny;
use HTML::Escape qw(escape_html);
use URI::Escape  qw(uri_escape_utf8);

has search_dir => (
  is      => 'ro',
  default => sub {
    my $self = shift;
    return Path::Tiny::path($self->app->config->{config}->{markdown_dir})->child('Searches');
  },
);

sub build ($self) {
  $self->register_routes($self->router);
}

sub register_routes ($self, $router) {
  $self->add_navigation_route('/Searches', 'Searches', { order => 25 });
  $self->add_navigation_route(
    '/Searches/Recommender',
    'AO3 Recommender',
    { order => 25 }
  );

  $router->add(
    '/Searches',
    {
      to => sub ($c, $ctx) {
        return $self->searches_index($ctx);
      },
      action => 'http.*',
    }
  );

  $router->add(
    '/Searches/Recommender',
    {
      to => async sub ($c, $ctx) {
        my $method = $ctx->req->method // 'GET';
        if (uc($method) eq 'POST') {
          return await $self->recommender_submit($ctx);
        }
        return $self->recommender_form($ctx);
      },
      action => 'http.*',
    }
  );

  $router->add(
    '/Searches/Recommender/stream',
    {
      to => sub ($c, $ctx) {
        return $self->recommender_stream($ctx);
      },
      action => 'sse.get',
    }
  );

  $self->log(info => "Registered Searches routes");
}

sub searches_index ($self, $ctx) {
  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation('/Searches');

  my $entry = {
    title => 'AO3 Recommender',
    path  => '/Searches/Recommender',
    type  => 'dynamic',
  };
  
  my $autoindex =
        $self->search_dir->is_dir
      ? $self->generate_directory_index($self->search_dir)
      : $self->generate_directory_index($self->search_dir->parent);

  push @{ $autoindex }, $entry;

  $autoindex = [ sort { $a->{title} cmp $b->{title} } $autoindex->@* ];

  return $self->template(
    'page/autoindex.tt',
    {
      title        => 'Searches',
      entries      => $autoindex,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/directory-list.css'],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo,
    }
  );
}

sub recommender_form ($self, $ctx) {
  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation('/Searches/Recommender');

  my $q = sub { $ctx->req->query_param($_[0]) // '' };

  return $self->template(
    'searches/recommender.tt',
    {
      title        => 'AO3 Recommender',
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/recommender.css'],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo,
      form_urls           => $q->('fic_urls'),
      form_wait           => $q->('wait_level'),
      form_blacklist      => $q->('blacklist_tags'),
      form_enforce        => $q->('enforce_tags'),
      form_soft           => $q->('soft_enforcement'),
      form_bkmrkr_limit   => $q->('bkmrkr_limit'),
      form_kdsr_limit     => $q->('kdsr_limit'),
      form_bkmrk_pages    => $q->('bkmrk_pages'),
      form_tag_page_limit => $q->('tag_page_limit'),
    }
  );
}

# POST: validate form, return page with JS that opens SSE stream
async sub recommender_submit ($self, $ctx) {
  my $form = await $ctx->req->form_params;
  my $body = $form->as_hashref;

  my $urls_raw   = $body->{fic_urls}       // '';
  my $wait_level = $body->{wait_level}     // 'long';
  my $blacklist  = $body->{blacklist_tags} // '';
  my $enforce    = $body->{enforce_tags}   // '';
  my $soft       = exists $body->{soft_enforcement} ? 1 : 0;

  # Advanced overrides (empty string = use preset default)
  my $bkmrkr_limit  = $body->{bkmrkr_limit}  // '';
  my $kdsr_limit    = $body->{kdsr_limit}     // '';
  my $bkmrk_pages   = $body->{bkmrk_pages}   // '';
  my $tag_page_limit = $body->{tag_page_limit} // '';

  my @urls = grep {length}
    map {s/^\s+|\s+$//gr}
    map {s{/\z}{}r}
    split /[\n,]+/, $urls_raw;

  unless (@urls) {
    return $self->_render_error($ctx,
      'Please provide at least one AO3 work URL.');
  }

  for my $url (@urls) {
    unless ($url =~ m{^https?://archiveofourown\.org/works/\d+}) {
      return $self->_render_error($ctx,
        "Invalid AO3 URL: " . escape_html($url));
    }
  }

  # Build query string for the SSE endpoint
  my $urls_param = uri_escape_utf8(join(',', @urls));
  my $qs         = join('&',
    "urls=$urls_param",
    "wait=" . uri_escape_utf8($wait_level),
    "blacklist=" . uri_escape_utf8($blacklist),
    "enforce=" . uri_escape_utf8($enforce),
    "soft=" . ($soft ? '1' : '0'),
    (length $bkmrkr_limit   ? ("bkmrkr_limit=$bkmrkr_limit")     : ()),
    (length $kdsr_limit      ? ("kdsr_limit=$kdsr_limit")         : ()),
    (length $bkmrk_pages     ? ("bkmrk_pages=$bkmrk_pages")      : ()),
    (length $tag_page_limit  ? ("tag_page_limit=$tag_page_limit") : ()),
  );

  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation('/Searches/Recommender');

  return $self->template(
    'searches/recommender_results.tt',
    {
      title          => 'AO3 Recommender - Results',
      current_year   => $current_year,
      css_files      => ['/css/navigation.css', '/css/recommender.css'],
      js_files       => ['/js/lib/recommender.js'],
      sidebar        => 1,
      nav_html       => $navigation_html,
      site_logo      => $self->site_logo,
      stream_qs      => $qs,
      form_urls      => $urls_raw,
      form_wait      => $wait_level,
      form_blacklist => $blacklist,
      form_enforce   => $enforce,
      form_soft      => $soft,
      form_bkmrkr_limit  => $bkmrkr_limit,
      form_kdsr_limit    => $kdsr_limit,
      form_bkmrk_pages   => $bkmrk_pages,
      form_tag_page_limit => $tag_page_limit,
    }
  );
}

# SSE endpoint: runs the recommender async, streams events
async sub recommender_stream ($self, $ctx) {
  my $sse = $ctx->sse;
  $ctx->consume;

  await $sse->start;
  await $sse->keepalive(25);

  $sse->on_close(sub {
    my ($s, $reason) = @_;
    $self->log(debug => "Recommender SSE closed: $reason");
  });

  # Parse params
  my $urls_raw  = $ctx->req->query_param('urls')      // '';
  my $wait      = $ctx->req->query_param('wait')      // 'long';
  my $blacklist = $ctx->req->query_param('blacklist') // '';
  my $enforce   = $ctx->req->query_param('enforce')   // '';
  my $soft      = $ctx->req->query_param('soft')      // '1';

  my @urls = grep {length} split /,/, $urls_raw;

  my $rec = App::Schierer::HPFan::View::Recommender->new();
  $rec->configure(
    wait_level       => $wait,
    blacklist        => $blacklist,
    enforce          => $enforce,
    soft_enforcement => ($soft eq '1' ? 1 : 0),
    bkmrkr_limit     => $ctx->req->query_param('bkmrkr_limit'),
    kdsr_limit       => $ctx->req->query_param('kdsr_limit'),
    bkmrk_pages      => $ctx->req->query_param('bkmrk_pages'),
    tag_page_limit   => $ctx->req->query_param('tag_page_limit'),
  );

  # Wire up progress callback
  $rec->on_progress(
    async sub ($msg) {
      return if $sse->is_closed;
      await $sse->send_event(
        event => 'progress',
        data  => { message => $msg },
      );
    }
  );

  # Wire up result callback - stream each new/updated result
  $rec->on_result(
      async sub ($row, $is_new) {
      return if $sse->is_closed;
      await $sse->send_event(event => 'row', data => $row,);
    }
  );

  # Run the recommender (async - yields to event loop on each HTTP request)
  my $results = await $rec->run(@urls);

  # Stream errors
  for my $err (@{ $rec->errors }) {
    last if $sse->is_closed;
    await $sse->send_event(
      event => 'error',
      data  => { message => $err },
    );
  }

  # Send final sorted results + complete signal
  unless ($sse->is_closed) {
    await $sse->send_event(
      event => 'final',
      data  => $results,
    );
    await $sse->send_event(
      event => 'complete',
      data  => { total => scalar @$results },
    );
  }

  await $sse->run unless $sse->is_closed;
  return;
}

sub _render_error ($self, $ctx, $message) {
  my $current_year    = (localtime)[5] + 1900;
  my $navigation_html = $self->render_navigation('/Searches/Recommender');

  return $self->template(
    'searches/recommender.tt',
    {
      title        => 'AO3 Recommender',
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/recommender.css'],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo,
      errors       => [$message],
    }
  );
}

1;
