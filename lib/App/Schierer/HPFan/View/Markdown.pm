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
        h1 => "spectrum-Heading spectrum-Heading--sizeXXL",
        h2 => "spectrum-Heading spectrum-Heading--sizeXL",
        h3 => "spectrum-Heading spectrum-Heading--sizeL",
        h4 => "spectrum-Heading spectrum-Heading--sizeM",
        h5 => "spectrum-Heading spectrum-Heading--sizeS",
        h6 => "spectrum-Heading spectrum-Heading--sizeXS",
      },
      timeline => {
        h1 => "spectrum-Heading spectrum-Heading--sizeL",
        h2 => "spectrum-Heading spectrum-Heading--sizeL",
        h3 => "spectrum-Heading spectrum-Heading--sizeM",
        h4 => "spectrum-Heading spectrum-Heading--sizeM",
        h5 => "spectrum-Heading spectrum-Heading--sizeS",
        h6 => "spectrum-Heading spectrum-Heading--sizeXS",
      }
    };

    my $spectrum_tags = {
      default => {
        p  => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeM',
        dt => 'spectrum-Detail spectrum-Detail--serif spectrum-Detail--sizeM'
        ,    # spectrum-Detail for citation labels
        dd => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeM',
        hr => 'spectrum-Divider spectrum-Divider--sizeM',
        li => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeM',
      },
      timeline => {
        p  => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeS',
        dt => 'spectrum-Detail spectrum-Detail--serif spectrum-Detail--sizeS'
        ,    # spectrum-Detail for citation labels
        dd => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeS',
        hr => 'spectrum-Divider spectrum-Divider--sizeS',
        li => 'spectrum-Body spectrum-Body--serif spectrum-Body--sizeS',
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
      $_->attr(class => $spectrum_tags->{$sizeTemplate}->{'hr'});
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
