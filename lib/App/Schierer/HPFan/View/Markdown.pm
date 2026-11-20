use v5.42;
use utf8::all;
use experimental qw(class);
#cspell: disable

#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require Pandoc;
require Path::Tiny;
use XML::LibXML;
require Mojo::DOM58;
require Log::Handler;

class App::Schierer::HPFan::View::Markdown {

  method logger {
    state $l4p //= Log::Handler->new();
    return $l4p;
  }

  field $markdownHome : param //= undef;
  field $asXHTML      = 0;
  field $sizeTemplate = 'default';

  ADJUST {
    $markdownHome = Path::Tiny::path($markdownHome) if defined($markdownHome);
  }

  # pandoc for future use
  field $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );

  method html5_to_xhtml_fragment ($html) {
    $html =~ s/<br\s*>/<br\/>/gi;
    $html =~ s/<hr\s*>/<hr\/>/gi;
    $html =~ s/<img([^>]*[^\/])>/<img$1\/>/gi;
    $html =~ s/<input([^>]*[^\/])>/<input$1\/>/gi;
    return $html;
  }

  method format_string ($snippet, $opts = {}) {
    $self->logger->trace("format_string recieved options: "
        . Data::Printer::np($opts, multiline => 0));
    $asXHTML      = $opts->{asXHTML}      if exists $opts->{asXHTML};
    $sizeTemplate = $opts->{sizeTemplate} if exists $opts->{sizeTemplate};

    my $parser       = Pandoc->new();
    my $html_content = $parser->convert(
      $customCommonMark => 'html5',
      $snippet
    );
    $html_content = $self->SpectrumFormatting($html_content);
    if ($asXHTML) {
      return $self->html5_to_xhtml_fragment($html_content);
    }
    return $html_content;
  }

  method SpectrumFormatting ($html_content) {
    my $dom = Mojo::DOM58->new($html_content);
    $self->logger->trace("requested size template is '$sizeTemplate'");

    my $spectrum_h = {
      default => {
        h1 => "swc-Heading swc-Heading--sizeXXL",
        h2 => "swc-Heading swc-Heading--sizeXL",
        h3 => "swc-Heading swc-Heading--sizeL",
        h4 => "swc-Heading swc-Heading--sizeM",
        h5 => "swc-Heading swc-Heading--sizeS",
        h6 => "swc-Heading swc-Heading--sizeXS",
      },
      timeline => {
        h1 => "swc-Heading swc-Heading--sizeL",
        h2 => "swc-Heading swc-Heading--sizeL",
        h3 => "swc-Heading swc-Heading--sizeM",
        h4 => "swc-Heading swc-Heading--sizeM",
        h5 => "swc-Heading swc-Heading--sizeS",
        h6 => "swc-Heading swc-Heading--sizeXS",
      }
    };

    my $spectrum_tags = {
      default => {
        p  => 'swc-Body swc-Body--serif swc-Body--sizeM',
        dt => 'swc-Detail swc-Detail--serif swc-Detail--sizeM'
        ,    # swc-Detail for citation labels
        dd => 'swc-Body swc-Body--serif swc-Body--sizeM',
        hr => 'm',
        li => 'swc-Body swc-Body--serif swc-Body--sizeM',
      },
      timeline => {
        p  => 'swc-Body swc-Body--serif swc-Body--sizeS',
        dt => 'swc-Detail swc-Detail--serif swc-Detail--sizeS'
        ,    # swc-Detail for citation labels
        dd => 'swc-Body swc-Body--serif swc-Body--sizeS',
        hr => 's',
        li => 'swc-Body swc-Body--serif swc-Body--sizeS',
      },
    };

    # Add header classes
    for my $tag (keys $spectrum_h->{$sizeTemplate}->%*) {
      $dom->find($tag)
        ->each(sub { $_->attr(class => $spectrum_h->{$sizeTemplate}->{$tag}) });
    }

    # Add paragraph classes
    $dom->find('p')->each(sub {
      $_->attr(class => $spectrum_tags->{$sizeTemplate}->{'p'});
    });

    # Add list item classes
    $dom->find('li')->each(sub {
      $_->attr(class => $spectrum_tags->{$sizeTemplate}->{'li'});
    });

    # Add link classes
    $dom->find('a')->each(sub {
      $_->attr(
        class => "swc-Link");
    });

    # No emphasis/strong classes: gen2 dropped Body-emphasized and Body-strong in favour
    # of the native <em> and <strong>, which this output already contains.

    # Gen2's divider is a custom element, not a class on <hr>. The size comes from the
    # same per-template table the classes used to.
    $dom->find('hr')->each(sub {
      $_->replace($dom->new_tag(
        'swc-divider', size => $spectrum_tags->{$sizeTemplate}->{'hr'}));
    });

    # One class on the <table>; styles/swc/table.css styles th/td/tr beneath it, so none
    # of the cells carries a class of its own.
    $dom->find('table')->each(sub {
      $_->attr(class => 'site-table');
    });

    # Convert back to HTML string
    my $styled_html = $dom->to_string;
    return $styled_html;
  }
}
1;
__END__
