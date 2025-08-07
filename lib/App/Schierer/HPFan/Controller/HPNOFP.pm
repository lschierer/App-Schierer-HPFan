use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
require Data::Printer;
require Mojolicious::Controller;
require Mojolicious::Plugin;
require HTML::HTML5::Writer;
require XML::LibXML;
require App::Schierer::HPFan::Model::Gramps;
use namespace::clean;

package App::Schierer::HPFan::Controller::HPNOFP {
  use Mojo::Base 'App::Schierer::HPFan::Controller::ControllerBase';
  use Log::Log4perl;
  use Path::Iterator::Rule;
  use HTML::Selector::XPath qw(selector_to_xpath);
  use Carp;

  my $navHtml;

  sub register($self, $app, $config //= {}) {

    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(__PACKAGE__ . " register function");

    my $distDir   = $app->config('distDir');
    my $HPNOFPSrc = $distDir->child('HPNOFP/src/OEBPS');

    my $rule = Path::Iterator::Rule->new;
    my $iter = $rule->file->name(qr/.xhtml$/)->iter($HPNOFPSrc);

    my $baseRoute =
      '/Fan Fiction/Harry Potter and the Nightmares of Futures Past';

    $app->routes->get($baseRoute)->to(
      controller => 'HPNOFP',
      action     => 'hpnofp_index',
    );

    # Add to navigation
    $app->add_navigation_item({
      title => 'Harry Potter and the Nightmares of Futures Past',
      path  => $baseRoute,
      order => 1,
    });

    while (my $file_path = $iter->()) {
      $file_path = Mojo::File->new($file_path);
      my $processed = $self->process_HPNOFP_OEBPS($file_path, $baseRoute);
      my $route     = $file_path->to_abs;
      $route =~ s{^\Q$HPNOFPSrc\E}{};
      $route =~ s{.xhtml$}{};
      $route = "$baseRoute$route";
      $route =~ s{//}{/}g;
      $logger->debug("using route '$route' for '$file_path'");

      $app->routes->get($route)->to(
        controller => 'HPNOFP',
        action     => 'hpnofp_page_handler',
        content    => $processed,
      );

      # Add to navigation
      $app->add_navigation_item({
        title => $processed->{title},
        path  => $route,
        order => $self->calculate_fanfiction_order($route, $baseRoute),
      });

    }

  }

  sub calculate_fanfiction_order($self, $path, $baseRoute) {
    # Remove the base path to work with just the relevant part
    my $relative_path = $path;
    $relative_path =~ s|^$baseRoute/||;

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

  sub hpnofp_index ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug(__PACKAGE__ . " hpnofp_index start");
    $c->stash(
      layout   => 'default',
      template => 'hpnofp/index',
      title    => 'Harry Potter and the Nightmares of Futures Past',
      nav      => defined($navHtml) ? $navHtml : '',
    );
    $c->render;
  }

  sub hpnofp_page_handler ($c) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug(__PACKAGE__ . " hpnofp_page_handler start");
    my $content = $c->stash('content');

    unless ($content) {
      $logger->error(sprintf(
        'No content present for call to hpnofp_page_handler for %s',
        $c->req->url->to_abs));
      $c->reply->not_found;
    }
    $c->stash(
      layout   => 'default',
      template => 'hpnofp/page',
      title    => $content->{title},
      nav      => defined($navHtml) ? $navHtml : '',
    );
    $c->render;
  }

  sub process_HPNOFP_OEBPS ($self, $file, $baseRoute) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(__PACKAGE__ . " process_HPNOFP_OEBPS start for $file");
    my $dom = XML::LibXML->load_html(
      location => $file,
      recover  => 1,
    );

    my $writer = HTML::HTML5::Writer->new(markup_declaration => 0,);

    my $name = $file->basename('.xhtml');

    # Add more debugging for h2 tag search
    my @h2nodes = $dom->findnodes('//h2');
    $logger->debug("Found " . scalar(@h2nodes) . " h2 nodes in $name");
    if (scalar(@h2nodes) > 0) {
      my $h2t = $h2nodes[0]->textContent;
      $logger->debug("First h2 content: $h2t");
    }
    else {
      $logger->debug("No h2 tags found in document");
    }

    my $titleNode = $h2nodes[0];
    my $titleText = $titleNode ? $titleNode->textContent : undef;

    $titleText //= "Harry Potter and the Nightmares of Futures Past - $name";

    $logger->debug("Using title: $titleText for $name");

    foreach my $linkNode ($dom->findnodes('//link[@href]')) {
      $linkNode->setAttribute('href', "/css/HPNOFP.css");
    }

    foreach my $anchorNode ($dom->findnodes('//a[@href]')) {
      my $target = $anchorNode->getAttribute('href');

      # Handle links with fragments
      if ($target =~ /^(.*)\.xhtml(#.*)?$/) {
        my $base     = $1;
        my $fragment = $2 || '';

      # If this is a link to a chapter or author notes, make it an absolute path
        if ($base =~ /^(Chapter\d+|AuthorNotes)$/) {
          $target = "$baseRoute/$base/$fragment";
        }
        else {
          # Otherwise, keep it as a relative path
          $target = "$base/$fragment";
          $target =~ s{//}{/}g;
        }
      }
      elsif ($target =~ /^#(.*)$/) {
        # Handle same-page fragments - keep as is
        $target = "#$1";
      }

      $anchorNode->setAttribute('href', $target);

      $logger->debug("Processed link: " . $anchorNode->getAttribute('href'));
    }

    foreach my $imgNode ($dom->findnodes('//img')) {
      my $cursrc = $imgNode->getAttribute('src');
      $cursrc = Mojo::File->new($cursrc);

      my $imgPath = sprintf("/images/HPNOFP/%s", $cursrc->basename);
      $imgNode->setAttribute('src', $imgPath);
    }

    my $bt        = $dom->findnodes('//body')->[0];
    my $article   = $dom->createElement('article');
    my $deepClone = 1;
    foreach my $child ($bt->childNodes()) {
      my $imported = $child->cloneNode($deepClone);
      $article->appendChild($imported);
    }

    # Get the body element as a string without the DOCTYPE
    # Use the element method directly which handles a single node
    my $html = $writer->element($article);

    if ($titleText eq 'Table of Contents') {

# This is the TOC file, so we need to extract the nav element and save it separately
      $logger->debug("Found TOC file, extracting nav fragment");

      # Find the nav element (or main element if that's what contains the TOC)
      my $navXpath   = selector_to_xpath('.coverpage');
      my $navElement = $dom->findnodes($navXpath)->[0];
      if (!$navElement) {
        # If there's no nav element, try to find the main element
        $navElement = $dom->findnodes('//main')->[0];
        $logger->debug("No nav element found, using main element instead");

      }

      if ($navElement) {
        $navElement->removeAttribute('epub:type');
        # Create a new HTML fragment file with just the nav content

        $navHtml = $writer->element($navElement);
        $navHtml =~ s{
            (<a\s+[^>]*?href=")      # Start of the href attribute
            (?!https?:|/|\.\.)       # Skip already absolute or protocol-based URLs
            ([^"]+)                  # Capture relative path (e.g., 'Year1/')
            (")                      # Closing quote
        }{$1$baseRoute/$2$3}xg;

      }
      else {
        $logger->warn("Could not find nav or main element in TOC file");
      }
    }

# on visual inspection, the files do not contain the author in predictable places.
# There are however only a few of them, so just hard code it based on the titles.
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
}
1;
__END__
