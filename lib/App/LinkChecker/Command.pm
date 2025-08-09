use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Log::Log4perl;
require Data::Printer;
require HTTP::Tiny;
require HTML::LinkExtor;
require URI;

require App::Schierer::HPFan::Logger::Config;

class App::LinkChecker::Command {
  use List::AllUtils qw( any none );
  use URI::Escape    qw(uri_unescape);
  use namespace::autoclean;
  use Carp;
  our $VERSION = 'v0.30.0';

  field $debug    : param //= 0;
  field $external : param //= 1;

  field $startUrl : param;
  field %checked_urls;
  field @urls_to_check;
  field $start_hostname;
  field $logger;

  field $previous_request_was_external;

  field $site_origin;

  field $http = HTTP::Tiny->new(
    max_redirect    => 10,    # follow up to 10 redirects
    timeout         => 60,
    agent           => 'Mozilla/5.0 (compatible; LinkChecker/1.0)',
  );

  ADJUST {
    # IMPORTANT: seed raw URL so start-url fragments get checked
    push @urls_to_check, $startUrl;

    my $u       = URI->new($startUrl);
    my $port    = $u->port;
    my $default = ($u->scheme eq 'http' && $port == 80)
      || ($u->scheme eq 'https' && $port == 443);
    my $port_part = $default ? '' : ":$port";
    $site_origin = sprintf('%s://%s%s', $u->scheme, lc($u->host), $port_part);

    $start_hostname = lc $u->host;
  }

  ADJUST {
    my $lc =
      App::Schierer::HPFan::Logger::Config->new('App-LinkChecker-Command');

    if ($debug) {
      my $log4perl_logger = $lc->init('development');
    }
    else {
      my $log4perl_logger = $lc->init('testing');
    }

    $logger = Log::Log4perl->get_logger(__CLASS__);
  }

  method execute {
    $logger->info("Starting checking at '$startUrl'; external link checking is "
        . ($external ? 'enabled' : 'disabled'));

    while (@urls_to_check) {
      my $url = shift @urls_to_check;    # FIFO
      $self->check_url($url);
    }

    $logger->info("Url Checking complete");

    # One final pass to resolve any base-page children still 'pending'
    $self->update_children_statuses();

    # Reporting
    for my $page (sort keys %checked_urls) {
      my $pstat = $checked_urls{$page}->{status} // 'unknown';
      if ($pstat =~ /^3/ || $pstat eq 'pending' || $pstat eq 'unknown') {
        # ignore or print as informational if you like
      }
      elsif ($pstat !~ /^2/ && $pstat ne 'skipped' && $pstat ne '403') {
        say "Found Broken Link to '$page'";
      }

      next unless exists $checked_urls{$page}->{children};
      for my $child (sort keys %{ $checked_urls{$page}->{children} }) {
        my $cstat = $checked_urls{$page}->{children}->{$child} // 'unknown';

        next if $cstat eq 'pending' || $cstat eq 'unknown';    # <-- important

        my $is_fragment = index($child, '#') >= 0;
        my $is_broken   = ($cstat eq '404-fragment')
          || ($cstat ne 'skipped' && $cstat ne '403' && $cstat !~ /^2/);

        if ($is_broken) {
          if ($is_fragment) {
            say "Page '$page' contains Broken Anchor '$child'.";
          }
          else {
            say "Page '$page' contains Broken Link to '$child'.";
          }
        }
      }
    }
  }

  method check_url ($url, $recurse = 1) {
    # Canonical base (no fragment) for keying
    my $canon       = $self->canonical($url);    # string
    my $orig        = URI->new($url);            # may have fragment
    my $is_external = (fc($orig->host) ne fc($start_hostname));

    if ($is_external) {
      if ($previous_request_was_external) {
        sleep(1);
      }
      $previous_request_was_external = 1;
    }
    else {
      $previous_request_was_external = 0;
    }

    if (exists $checked_urls{$canon}->{status}) {
      $logger->debug(sprintf('"%s" has already been checked (status="%s"). Skipping.',
      $canon, $checked_urls{$canon}->{status}));
      return $checked_urls{$canon}->{status};
    }

    $logger->info("Checking $canon");
    my $response = $http->get($canon);
    $checked_urls{$canon}->{status} = $response->{status};

    unless ($response->{success}) {
      $logger->warn(sprintf(
        'Detected Broken page %s via status %s - %s.',
        $canon, $response->{status}, $response->{reason}
      ));
      return $response->{status};
    }

    $logger->debug(
      sprintf('Page %s returned status %s.', $canon, $response->{status}));

    my $content = $response->{content} // '';

    # Build anchor index for this page
    my %anchors;
    while ($content =~ /<([A-Za-z][^>\s]*)\s[^>]*\bid=["']([^"']+)["'][^>]*>/g)
    {
      $anchors{$2} = 1;
    }
    while ($content =~ /<a\s[^>]*\bname=["']([^"']+)["'][^>]*>/g) {
      $anchors{$1} = 1;
    }
    $checked_urls{$canon}->{anchors} = \%anchors;

    # Resolve any pending fragments queued for this base page
    if (my $pend = delete $checked_urls{$canon}->{pending_fragments}) {
      for my $frag (keys %$pend) {
        my $ok = exists $anchors{$frag};
        $checked_urls{$canon}->{children}->{"$canon#$frag"} =
          $ok ? 200 : '404-fragment';
      }
    }

  # If this *request* had a fragment, validate it (without altering page status)
    if (my $frag = $orig->fragment) {
      $frag = uri_unescape($frag);
      my $ok = exists $anchors{$frag};
      $checked_urls{$canon}->{children}->{"$canon#$frag"} =
        $ok ? 200 : '404-fragment';
    }

    # Recurse: parse links unless this is a static asset
    my $req_uri = URI->new($canon);
    if ($recurse && $req_uri->path !~ /\.(?:css|js|png|jpg|gif|pdf)$/i) {
      my $extractor = HTML::LinkExtor->new(undef, $canon);
      $extractor->parse($content);
      my @links = $extractor->links;
      $logger->info(sprintf('parsed %d links from %s', scalar @links, $canon));

      my $hostname = URI->new($canon)->host // '';
      $logger->info("extracted hostname $hostname for request");

      # sorting the links gives me a semi-predictable order it will progress
      # through the overall site
      for my $link_array (sort @links) {
        my ($tag, %attrs) = @$link_array;
        my $href = $attrs{href} || $attrs{src} or next;

        my $abs  = URI->new($href)->abs($canon);
        my $base = $self->canonical($abs);         # encoded, no fragment
        my $frag = $abs->fragment;
        $frag = uri_unescape($frag) if defined $frag;

        # Internal if it starts with the site origin
        my $is_internal = index($base, $site_origin) == 0;

        # Same-page?
        my $parent_base  = $canon;
        my $is_same_page = ($parent_base eq $base);

        # Queue internal
        unless (exists $checked_urls{$base}
          || grep { $_ eq $base } @urls_to_check) {
          if ($is_internal && !$is_same_page) {
            push @urls_to_check, $base;
            $logger->info("queued $base from $parent_base");
          }
          elsif (!$is_same_page && $external) {
            $self->check_single_url($base);
          }
          elsif (!$is_same_page && !$external) {
            $checked_urls{$base}->{status} = 'skipped';
          }
        }

        # Record relationship from parent to child (base or base#frag)
        if (defined $frag && length $frag) {
          my $child_key = "$base#$frag";
          $checked_urls{$parent_base}->{children}->{$child_key} = 'pending';

          if (my $anch = $checked_urls{$base}->{anchors}) {
            my $ok = exists $anch->{$frag};
            $checked_urls{$parent_base}->{children}->{$child_key} =
              $ok ? 200 : '404-fragment';
          }
          else {
            $checked_urls{$base}->{pending_fragments}->{$frag} = 1;
          }
        }
        else {
          my $child_status = $checked_urls{$base}->{status};
          $checked_urls{$parent_base}->{children}->{$base} //=
            (defined $child_status ? $child_status : 'pending');
        }
      }
    }

    return $response->{status};
  }

  method check_single_url ($url) {
    # This method checks a single URL without recursion (for external links)

    my $uri = URI->new($url);
    my $is_external = (fc($uri->host) ne fc($start_hostname));

    if ($uri->host ne $start_hostname and not $external) {
      $logger->debug(sprintf(
        'host "%s" is not "%s" and external set to %s - marking as skipped',
        $uri->host, $start_hostname, $external ? 'true' : 'false'
      ));
      $checked_urls{$url}->{status} = 'skipped';
      return 'skipped';
    }

    if (exists $checked_urls{$url}) {
      $logger->debug("$url has already been checked. Skipping.");
      return $checked_urls{$url}->{status};
    }

    $logger->info("Checking external URL $url (no recursion)");

    my $response = $http->get($url, {
    headers => $is_external ?{
            'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language' => 'en-US,en;q=0.5',
            'Accept-Encoding' => 'gzip, deflate',
            'DNT' => '1',
            'Connection' => 'keep-alive',
            'Upgrade-Insecure-Requests' => '1',
        } : {},
    });
    $checked_urls{$url}->{status} = $response->{status};

    unless ($response->{success}) {
      $logger->warn(sprintf(
        'Detected Broken external page %s via status %s - %s.',
        $url, $response->{status}, $response->{reason}
      ));
    }
    else {
      $logger->debug(sprintf(
        'External page %s returned status %s.',
        $url, $response->{status}
      ));
    }

    return $response->{status};
  }

  method update_children_statuses {
    for my $parent (keys %checked_urls) {
      next unless exists $checked_urls{$parent}->{children};

      for my $child (keys %{ $checked_urls{$parent}->{children} }) {
        next unless $checked_urls{$parent}->{children}->{$child} eq 'pending';

        # Fragment children are resolved when the base page is fetched
        next if index($child, '#') >= 0;

        # Base page child: copy status if we have it
        if (exists $checked_urls{$child}->{status}) {
          $checked_urls{$parent}->{children}->{$child} =
            $checked_urls{$child}->{status};
        }
        # else still pending; will resolve after that page is fetched
      }
    }
  }

  method canonical ($u) {
    my $uri = URI->new("$u");

    $uri->fragment(undef);

    if (my $host = $uri->host) {
      $uri->host(lc $host);
    }

    if (($uri->scheme || '') eq 'http' && ($uri->port || 0) == 80) {
      $uri->port(undef);
    }
    if (($uri->scheme || '') eq 'https' && ($uri->port || 0) == 443) {
      $uri->port(undef);
    }

    my $path = $uri->path // '';
    if ($path ne '/' && $path =~ s{/$}{}) {
      $uri->path($path);
    }

    return $uri->as_string;
  }

}
1;
__END__
