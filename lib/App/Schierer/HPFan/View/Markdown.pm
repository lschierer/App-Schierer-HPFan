use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require Pandoc;
require Path::Tiny;
use XML::LibXML;
require Mojo::DOM58;

class App::Schierer::HPFan::View::Markdown
  : isa(App::Schierer::HPFan::Logger) {

  field $markdownHome : param //= undef;

  ADJUST {
    $markdownHome = Path::Tiny::path($markdownHome) if defined($markdownHome);
  }

  # pandoc for future use
  field $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );

  method html5_to_xhtml_fragment ($html) {
      my $XHTML_NS = 'http://www.w3.org/1999/xhtml';

      my $p   = XML::LibXML->new(recover => 1);
      my $tmp = $p->load_html(string => "<div id='__frag'>$html</div>");
      my ($root) = $tmp->findnodes('//*[@id="__frag"]');
      return '' unless $root;

      my $xml  = XML::LibXML::Document->new('1.0', 'UTF-8');
      my $host = $xml->createElementNS($XHTML_NS, 'div');
      $xml->setDocumentElement($host);

      for my $child ($root->childNodes) {
        my $imp = $self->_import_as_xhtml($xml, $child, $XHTML_NS);
        $host->appendChild($imp) if $imp;
      }

      my $out = '';
      $out .= $_->toString for $host->childNodes;   # inner XML only
      return $out;
    }

  method _import_as_xhtml ($doc, $node, $ns) {
      return $doc->importNode($node, 1)
        if $node->nodeType != XML_ELEMENT_NODE;

      my $new = $doc->createElementNS($ns, $node->nodeName);
      for my $attr ($node->attributes) {
        $new->setAttribute($attr->nodeName, $attr->getValue);
      }
      for my $ch ($node->childNodes) {
        my $imp = $self->_import_as_xhtml($doc, $ch, $ns);
        $new->appendChild($imp) if $imp;
      }
      return $new;
    }


  method format_string ($snippet, $asXHTML = 0) {
    my $parser = Pandoc->new();
    my $html_content = $parser->convert(
      $customCommonMark => 'html5',
      $snippet
    );
    $html_content = $self->SpectrumFormatting($html_content);
    if($asXHTML) {
      return $self->html5_to_xhtml_fragment($html_content);
    }
    return $html_content;
  }

  method SpectrumFormatting ( $html_content) {
    my $dom = Mojo::DOM58->new($html_content);

    my %spectrum_h = (
      h1 => "spectrum-Heading spectrum-Heading--sizeXXL",
      h2 => "spectrum-Heading spectrum-Heading--sizeXL",
      h3 => "spectrum-Heading spectrum-Heading--sizeL",
      h4 => "spectrum-Heading spectrum-Heading--sizeM",
      h5 => "spectrum-Heading spectrum-Heading--sizeS",
      h6 => "spectrum-Heading spectrum-Heading--sizeXS",
    );

    # Add header classes
    for my $tag (keys %spectrum_h) {
      $dom->find($tag)->each(sub { $_->attr(class => $spectrum_h{$tag}) });
    }

    # Add paragraph classes
    $dom->find('p')->each(sub {
      $_->attr(
        class => "spectrum-Body spectrum-Body--serif spectrum-Body--sizeM");
    });

    # Add list item classes
    $dom->find('li')->each(sub {
      $_->attr(
        class => "spectrum-Body spectrum-Body--serif spectrum-Body--sizeM");
    });

    # Add link classes
    $dom->find('a')->each(sub {
      $_->attr(
        class => "spectrum-Link spectrum-Link--primary spectrum-Link--quiet");
    });

    # Add emphasis class
    $dom->find('em')->each(sub {
      $_->attr(class => "spectrum-Body-emphasized");
    });

    # Add strong class
    $dom->find('strong')->each(sub {
      $_->attr(class => "spectrum-Body-strong");
    });

    $dom->find('hr')->each(sub {
      $_->attr(class => 'spectrum-Divider spectrum-Divider--sizeM');
    });

    # Add table classes
    $dom->find('table')->each(sub {
      $_->attr(class => 'spectrum-Table spectrum-Table--sizeM');
    });

    $dom->find('thead')->each(sub {
      $_->attr(class => 'spectrum-Table-head');
    });

    $dom->find('tbody')->each(sub {
      $_->attr(class => 'spectrum-Table-body');
    });

    $dom->find('th')->each(sub {
      $_->attr(class => 'spectrum-Table-headCell');
    });

    $dom->find('td')->each(sub {
      $_->attr(class => 'spectrum-Table-cell');
    });

    $dom->find('tr')->each(sub {
      $_->attr(class => 'spectrum-Table-row');
    });

    # Convert back to HTML string
    my $styled_html = $dom->to_string;
    return $styled_html;
  }
}
1;
__END__
