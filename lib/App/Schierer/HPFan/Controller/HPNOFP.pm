package App::Schierer::HPFan::Controller::HPNOFP;

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
extends 'Thunderhorse::Controller';
with 'WebFramework::Role::Logger';

use Path::Tiny;
use Path::Iterator::Rule;
use XML::LibXML;
use HTML::HTML5::Writer;
use HTML::Selector::XPath qw(selector_to_xpath);
use Scalar::Util          qw(blessed);

has site_logo => (
  is      => 'ro',
  default => '',
);

has hpnofp_dir => (
  is      => 'ro',
  default => sub { path('share/HPNOFP/src/OEBPS') },
);

has base_route => (
  is      => 'ro',
  default => '/Fan Fiction/Harry Potter and the Nightmares of Futures Past',
);

has nav_html => (
  is      => 'rw',
  default => '',
);

has pages => (is => 'lazy');

sub _build_pages ($self) {
  my %pages;

  my $rule = Path::Iterator::Rule->new;
  my $iter = $rule->file->name(qr/\.xhtml$/)->iter($self->hpnofp_dir);

  while (my $file_path = $iter->()) {
    $file_path = path($file_path);

    my $processed = $self->process_xhtml_file($file_path);
    next unless $processed;

    # Calculate route from file path
    my $route = $file_path->absolute->stringify;
    $route =~ s{^\Q@{[$self->hpnofp_dir->absolute]}\E}{};
    $route =~ s{\.xhtml$}{};
    $route = $self->base_route . $route;
    $route =~ s{//}{/}g;

    $self->logger->debug("Registering route '$route' for '$file_path'");

    $pages{$route} = $processed;
  }

  return \%pages;
}

sub build ($self) {
  $self->register_routes($self->router);
}

sub register_routes ($self, $router) {
  my $pages = $self->pages;

  # Register base index route
  $self->add_navigation_route(
    $self->base_route,
    'Harry Potter and the Nightmares of Futures Past',
    { order => 1 }
  );

  $router->add(
    $self->base_route,
    {
      to => sub ($self, $ctx) {
        return $self->index_handler($ctx);
      },
      action => 'http.get',
    }
  );

  # Register all page routes
  for my $route (sort keys %$pages) {
    my $content = $pages->{$route};

    $self->add_navigation_route($route, $content->{title},
      { order => $self->calculate_fanfiction_order($route) });

    $router->add(
      $route,
      {
        to => sub ($self, $ctx) {
          return $self->page_handler($ctx, $content);
        },
        action => 'http.get',
      }
    );
  }

  $self->logger->info("Registered " . scalar(keys %$pages) . " HPNOFP routes");
}

sub calculate_fanfiction_order ($self, $path) {
  # Remove the base path to work with just the relevant part
  my $relative_path = $path;
  $relative_path =~ s|^@{[$self->base_route]}/||;

  # TOC gets order 1
  if ($relative_path eq 'TOC' || $relative_path =~ /\/TOC$/) {
    return 1;
  }

  # Year paths: order = year + (year - 1) * 10
  if ($relative_path =~ /Year(\d+)/) {
    my $year = $1;
    return 2  if $year == 1;
    return 10 if $year == 2;
    return 29 if $year == 3;
    return 41 if $year == 4;
    return 1;
  }

  # Chapter paths: order = 1 + chapter_number
  if ($relative_path =~ /Chapter(\d+)/) {
    my $chapter = $1;
    return 1 + $chapter;
  }

  # Appendix and AuthorsNotes get order 1000
  if ($relative_path =~ /^Appendix/) {
    return 999 if $relative_path =~ /^Appendix$/;
    return 1000;
  }

  # Default order for anything else
  return 500;
}

sub index_handler ($self, $ctx) {
  my $current_path    = $ctx->req->path;
  my $navigation_html = $self->render_navigation($current_path);

  my $vars = {
    title        => 'Harry Potter and the Nightmares of Futures Past',
    current_year => (localtime)[5] + 1900,
    css_files    => ['/css/navigation.css', '/css/HPNOFP.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo,
  };

  return $self->render('hpnofp/index.tt', $vars);
}

sub page_handler ($self, $ctx, $content) {
  my $current_path    = $ctx->req->path;
  my $navigation_html = $self->render_navigation($current_path);

  my $vars = {
    content      => $content,
    title        => $content->{title},
    current_year => (localtime)[5] + 1900,
    css_files    => ['/css/navigation.css', '/css/HPNOFP.css'],
    sidebar      => 1,
    nav_html     => $navigation_html,
    site_logo    => $self->site_logo,
  };

  return $self->render('hpnofp/page.tt', $vars);
}

sub process_xhtml_file ($self, $file) {
  $self->logger->info("Processing XHTML file: $file");

  my @warns;
  local $SIG{__WARN__} = sub { push @warns, @_ };

  my $dom;
  my $ok = eval {
    $dom = XML::LibXML->load_html(
      location => $file->stringify,
      recover  => 1,
    );
    1;
  };

  if (!$ok) {
    my $err = $@;
    if (blessed($err) && $err->isa('XML::LibXML::Error')) {
      chomp(my $msg = $err->as_string);
      $self->logger->error($msg);
    }
    else {
      chomp $err;
      $self->logger->error("XML::LibXML load_html failed: $err");
    }
    return undef;
  }

  # Log warnings
  for my $w (@warns) {
    chomp $w;
    $self->logger->warn($w);
  }

  my $writer = HTML::HTML5::Writer->new(markup_declaration => 0);

  my $name = $file->basename('.xhtml');

  # Extract title from h2 tag
  my @h2nodes = $dom->findnodes('//h2');
  $self->logger->debug("Found " . scalar(@h2nodes) . " h2 nodes in $name");

  my $titleNode = $h2nodes[0];
  my $titleText = $titleNode ? $titleNode->textContent : undef;
  $titleText //= "Harry Potter and the Nightmares of Futures Past - $name";

  $self->logger->debug("Using title: $titleText for $name");

  # Fix CSS links
  foreach my $linkNode ($dom->findnodes('//link[@href]')) {
    $linkNode->setAttribute('href', "/css/HPNOFP.css");
  }

  # Fix anchor links
  foreach my $anchorNode ($dom->findnodes('//a[@href]')) {
    my $target = $anchorNode->getAttribute('href');

    # Handle links with fragments
    if ($target =~ /^(.*)\.xhtml(#.*)?$/) {
      my $base     = $1;
      my $fragment = $2 || '';

      # If this is a link to a chapter or author notes, make it an absolute path
      if ($base =~ /^(Chapter\d+|AuthorNotes)$/) {
        $target = $self->base_route . "/$base$fragment";
      }
      else {
        # Otherwise, keep it as a relative path
        $target = "$base$fragment";
        $target =~ s{//}{/}g;
      }
    }
    elsif ($target =~ /^#(.*)$/) {
      # Handle same-page fragments - keep as is
      $target = "#$1";
    }

    $anchorNode->setAttribute('href', $target);
  }

  # Fix image paths
  foreach my $imgNode ($dom->findnodes('//img')) {
    my $cursrc   = $imgNode->getAttribute('src');
    my $img_file = path($cursrc);

    my $imgPath = "/images/HPNOFP/" . $img_file->basename;
    $imgNode->setAttribute('src', $imgPath);
  }

  # Extract body content as article
  my $bt        = $dom->findnodes('//body')->[0];
  my $article   = $dom->createElement('article');
  my $deepClone = 1;
  foreach my $child ($bt->childNodes()) {
    my $imported = $child->cloneNode($deepClone);
    $article->appendChild($imported);
  }

  my $html = $writer->element($article);

  # Extract TOC navigation if this is the TOC file
  if ($titleText eq 'Table of Contents') {
    $self->logger->debug("Found TOC file, extracting nav fragment");

    my $navXpath   = selector_to_xpath('.coverpage');
    my $navElement = $dom->findnodes($navXpath)->[0];
    if (!$navElement) {
      $navElement = $dom->findnodes('//main')->[0];
      $self->logger->debug("No nav element found, using main element instead");
    }

    if ($navElement) {
      $navElement->removeAttribute('epub:type');
      my $nav_html = $writer->element($navElement);

      # Fix relative links in navigation
      $nav_html =~ s{
                (<a\s+[^>]*?href=")      # Start of the href attribute
                (?!https?:|/|\.\.)       # Skip already absolute or protocol-based URLs
                ([^"]+)                  # Capture relative path (e.g., 'Year1/')
                (")                      # Closing quote
            }{$1@{[$self->base_route]}/$2$3}xg;

      $self->nav_html($nav_html);
    }
    else {
      $self->logger->warn("Could not find nav or main element in TOC file");
    }
  }

  # Determine author based on title
  my $author = '';
  if ($titleText =~ /A Night at The Burrow/) {
    $author = 'Worfe';
  }
  elsif ($titleText =~ /G for Ginevra/) {
    $author = 'Peach Wookiee';
  }
  else {
    $author = 'Matthew Schocke';
  }

  return {
    title  => $titleText,
    author => $author,
    html   => $html,
  };
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Controller::HPNOFP - Controller for Harry Potter and the Nightmares of Futures Past

=head1 DESCRIPTION

Thunderhorse controller that processes and serves XHTML files from the HPNOFP
ebook, converting them to HTML pages with proper navigation and styling.

=cut
