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

  use namespace::autoclean;
  use Carp;
  our $VERSION = 'v0.30.0';

  field $debug : param //= 0;
  field $external :param //= 1;

  field $startUrl : param;
  field %checked_urls;
  field @urls_to_check;
  field $start_hostname;
  field $logger;

  ADJUST {
    push @urls_to_check, $startUrl;
    # Extract hostname from start URL for domain checking
    $start_hostname = URI->new($startUrl)->host;
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
    $logger->info("Starting checking at '$startUrl'; external link checking is " . ($external ? 'enabled' : 'disabled'));

    # Process queue until empty
    while (@urls_to_check) {
      my $url = shift @urls_to_check;    # FIFO: take from front
      $self->check_url($url);
    }

    $logger->info("Url Checking complete");

    # Update children statuses now that all URLs are processed
    $self->update_children_statuses();

    foreach my $checked (sort keys %checked_urls) {
      if ($checked_urls{$checked}->{status} !~ /^2/ && $checked_urls{$checked}->{status} ne 'skipped') {
        say "Found Broken Link to $checked";
      }
      elsif (exists $checked_urls{$checked}->{children}) {
        foreach my $child (sort keys %{ $checked_urls{$checked}->{children} }) {
          if ($checked_urls{$checked}->{children}->{$child} !~ /^2/ && $checked_urls{$checked}->{children}->{$child} ne 'skipped') {
            say "Page $checked contains Broken Link to $child.";
          }
        }
      }
    }
  }

  method check_url ($url, $recurse = 1) {
    # Remove fragment for checking purposes
    my $uri = URI->new($url);

    if (exists $checked_urls{$url}) {
      $logger->debug("$url has already been checked. Skipping.");
      return $checked_urls{$url}->{status};
    }

    $logger->info("Checking $url");

    my $response = HTTP::Tiny->new->get($url);
    $checked_urls{$url}->{status} = $response->{status};

    unless ($response->{success}) {
      $logger->warn(sprintf(
        'Detected Broken page %s via status %s - %s.',
        $url, $response->{status}, $response->{reason}
      ));
      return $response->{status};
    }

    $logger->debug(
      sprintf('Page %s returned status %s.', $url, $response->{status}));

    if ($response->{content} && length($response->{content}) && $recurse) {
      my $content = $response->{content};
      if (length($uri->fragment)) {
        my $frag           = $uri->fragment;
        my $fragment_found = 0;

        # Check for id attributes on any element
        if ($content =~ /<[^>]+id=[\'\"]$frag[\'\"][^>]*>/i) {
          $fragment_found = 1;
        }
        # Check for name attributes (older anchor style)
        elsif ($content =~ /<a[^>]+name=[\'\"]$frag[\'\"][^>]*>/i) {
          $fragment_found = 1;
        }

        unless ($fragment_found) {
          $logger->warn("Fragment #$frag NOT found on page $url");
          $checked_urls{$url}->{status} =
            404;    # Override the successful page status
          return 404;
        }
      }
      if ($uri->path !~ /\.(css|js|png|jpg|gif|pdf)$/i)
      {    # cannot find links to check in these files.
        my $extractor = HTML::LinkExtor->new(undef, $url);
        $extractor->parse($response->{content});
        my @links = $extractor->links;

        my $hostname = $uri->host;
        $logger->info("extracted hostname $hostname");

        foreach my $link_array (sort @links) {
          my ($tag, %attrs) = @$link_array;
          my $href = $attrs{href} || $attrs{src};

          if ($href) {
            my $abs_uri = URI->new($href)->abs($url);
            $logger->trace("found url to check: $abs_uri");

            unless ($abs_uri->scheme eq 'mailto') {    # Avoid email links
              my $abs_url_str = $abs_uri->as_string;

              # Check if this is a same-page link (fragment-only or same URL without fragment)
              my $current_uri = URI->new($url);
              my $is_same_page = 0;

              # Remove fragments for comparison
              my $current_without_fragment = $current_uri->clone;
              $current_without_fragment->fragment(undef);
              my $target_without_fragment = $abs_uri->clone;
              $target_without_fragment->fragment(undef);

              if ($current_without_fragment->eq($target_without_fragment)) {
                $is_same_page = 1;
                $logger->debug("Skipping same-page link: $abs_url_str");
              }

              # Check if URL is already processed
              unless (exists $checked_urls{$abs_url_str}) {
                # Check if already in queue to avoid duplicates
                unless (grep { $_ eq $abs_url_str } @urls_to_check) {
                  # Only add to queue for recursive checking if it's the same domain AND not same page
                  if ($start_hostname eq $abs_uri->host && !$is_same_page) {
                    push @urls_to_check,
                      $abs_url_str; # Add to end of queue for recursive checking
                    $logger->debug(sprintf(
                    'Added internal URL "%s" to queue for recursive checking',
                    $abs_url_str));
                  }
                  elsif (!$is_same_page && $external) {
                    # External URL - check it directly but don't recurse (only if external checking enabled)
                    $self->check_single_url($abs_url_str);
                    $logger->debug(
"Checked external URL $abs_url_str directly (no recursion)"
                    );
                  }
                  elsif (!$is_same_page && !$external) {
                    # External URL but external checking disabled - mark as skipped
                    $checked_urls{$abs_url_str}->{status} = 'skipped';
                    $logger->debug("Skipped external URL $abs_url_str (external checking disabled)");
                  }
                }
              }

              # Mark the relationship for later status update (unless it's same-page)
              unless ($is_same_page) {
                $checked_urls{$url}->{children}->{$href} = 'pending';
              }
            }
          }
        }
      }

    }

    return $response->{status};
  }

  method check_single_url ($url) {
    # This method checks a single URL without recursion (for external links)

    my $uri = URI->new($url);
    if ($uri->host ne $start_hostname and not $external) {
      $logger->debug(sprintf('host "%s" is not "%s" and external set to %s - marking as skipped',
      $uri->host, $start_hostname, $external ? 'true' : 'false'));
      $checked_urls{$url}->{status} = 'skipped';
      return 'skipped';
    }

    if (exists $checked_urls{$url}) {
      $logger->debug("$url has already been checked. Skipping.");
      return $checked_urls{$url}->{status};
    }

    $logger->info("Checking external URL $url (no recursion)");

    my $response = HTTP::Tiny->new->get($url);
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
    foreach my $parent_url (keys %checked_urls) {
      next unless exists $checked_urls{$parent_url}->{children};

      foreach my $child_href (keys %{ $checked_urls{$parent_url}->{children} })
      {
        next
          unless $checked_urls{$parent_url}->{children}->{$child_href} eq
          'pending';

        # Convert relative href to absolute URL to find in checked_urls
        my $abs_uri     = URI->new($child_href)->abs($parent_url);
        my $abs_url_str = $abs_uri->as_string;

        if (exists $checked_urls{$abs_url_str}) {
          $checked_urls{$parent_url}->{children}->{$child_href} =
            $checked_urls{$abs_url_str}->{status};
        }
        else {
          $logger->warn("Could not find status for child URL: $abs_url_str");
          $checked_urls{$parent_url}->{children}->{$child_href} = 'unknown';
        }
      }
    }
  }

}
1;
__END__
