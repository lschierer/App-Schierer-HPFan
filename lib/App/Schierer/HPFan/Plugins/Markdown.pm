use v5.42.0;
use experimental qw(class);
use utf8::all;
use File::FindLib 'lib';
use Mojo::File;
use Path::Iterator::Rule;
require Pandoc;
require Data::Printer;
require Scalar::Util;
require YAML::PP;
require Mojo::DOM58;
use namespace::autoclean;

package App::Schierer::HPFan::Plugins::Markdown {
  use Mojo::Base 'Mojolicious::Plugin', -strict, -signatures;
  use Carp;

  my $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );

  sub register ($self, $app, $config) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->info(sprintf('initializing %s.', __PACKAGE__));

    # Add helper method for rendering markdown files
    $app->helper(
      render_markdown_file => sub ($c, $file_path, $opts = {}) {
        $logger->debug(
          'render_markdown_file requested by $c ' . Scalar::Util::blessed($c));
        $logger->debug("render_markdown_file requested for '$file_path'");
        return $self->_render_markdown_file($c, $file_path, $opts);
      }
    );

    $app->helper(render_markdown_snippet => \&_render_markdown_snippet);
    $app->helper(spectrum_formatting     => \&SpectrumFormatting);

    $app->helper(
      parse_markdown_frontmatter => sub ($c, $file_path) {
        return $self->_parse_markdown_frontmatter($file_path);
      }
    );
  }

  sub _render_markdown_snippet ($self, $snippet) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    if (not defined $snippet or length($snippet) == 0) {
      $logger->warn('snippet must be present!!');
      return '';
    }

    my $parser       = Pandoc->new();
    my $html_content = $parser->convert(
      $customCommonMark => 'html',
      $snippet
    );
    $html_content = $self->app->spectrum_formatting($html_content);
    $logger->debug("html_content for snippet is $html_content");
    return $html_content;
  }

  sub _parse_markdown_frontmatter ($self, $file_path) {
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);

    unless ($file_path && $file_path->isa('Mojo::File')) {
      $logger->error("file_path must be a 'Mojo::File' not "
          . (ref($file_path) || 'undefined'));
      return 0;
    }

    unless (-f $file_path) {
      unless ((!-d $file_path) || (!-f $file_path->child('index.md'))) {
        $logger->error("Markdown file not found: $file_path");
        return 0;
      }
      $file_path = $file_path->child('index.md');
    }

    my $ypp = YAML::PP->new(
      schema       => [qw/ + Perl /],
      yaml_version => ['1.2', '1.1'],
    );

    my $front_matter = {};
    my $title        = $file_path->basename('.md');
    my $content      = $file_path->slurp('UTF-8');

    if ($content =~ s/^---\s*\n(.*?)\n---\s*\n//s) {
      my $yaml = $1;
      eval { $front_matter = $ypp->load_string($yaml); };
      if ($@) {
        $logger->error("Error parsing YAML front matter: $@");
      }
      elsif (ref $front_matter eq 'HASH') {
        # Use title from front matter if available
        $title = $front_matter->{title}
          if exists $front_matter->{title};
      }
    }

    my $order = exists $front_matter->{order} ? $front_matter->{order} : 0;
    return {
      title        => $title,
      order        => $order,
      front_matter => $front_matter,
      content      => $content,
    };
  }

  # Private method to render markdown file
  sub _render_markdown_file ($self, $c, $file_path, $opts = {}) {
    if (not defined $opts) {
      $opts = {};
    }
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);
    $logger->debug("stash at start of _render_markdown_file has keys "
        . join(", ", keys %{ $c->stash() }));

    unless ($file_path && $file_path->isa('Mojo::File')) {
      $logger->error("file_path must be a 'Mojo::File' not "
          . (ref($file_path) || 'undefined'));
      return $c->reply->not_found;
    }

    my $parsedFile = $self->_parse_markdown_frontmatter($file_path);
    unless ($parsedFile) {
      $logger->error("error parsing front matter for $file_path");
      return $c->reply->not_found;
    }

    # Only set stash values that aren't already set
    foreach my $key (keys %{ $parsedFile->{front_matter} }) {
      $c->stash($key => $parsedFile->{front_matter}->{$key})
        unless exists $c->stash->{$key};
    }

    # Only set title if not already set
    $c->stash(title => $parsedFile->{title}) unless exists $c->stash->{title};

    # Only set layout if not already set
    my $layout = $parsedFile->{front_matter}->{layout} // 'default';

    # splash is not actually a layout, it indicates there is no sidebar.
    if ($layout =~ /splash/i) {
      $c->stash(sidebar => 0);
      $layout = 'default';
      $c->stash(layout => 'default');
    }

    $c->stash(layout => $layout) unless exists $c->stash->{layout};
    $logger->debug("layout is " . $c->stash('layout'));

    my $template = $opts->{template} // $c->stash('template') // 'markdown';
    $logger->debug("Using template: $template");

    $logger->debug(
      "Template paths: " . join(", ", @{ $c->app->renderer->paths }));
    $logger->debug("Looking for template: $template.html.ep");

    my $parser = Pandoc->new();

    my $html_content = $parser->convert(
      $customCommonMark => 'html',
      $parsedFile->{content}
    );

    $html_content = $self->SpectrumFormatting($html_content);
    my $content = $c->stash('content') // $html_content;

    if (!exists $c->stash->{markdown_content}) {
      $c->stash(markdown_content => $html_content);
    }

    if ((
        $c->stash('front_matter')
        && exists $c->stash('front_matter')->{autoindex}
      )
      or $c->stash('autoindex')
    ) {
      my $directory       = $file_path->dirname;
      my $generated_index = $c->app->generate_directory_index($directory);

      $c->stash(generated_index => $generated_index);
    }

    $logger->debug("finally decided on template $template");
    return $c->render(
      template => $template,
      layout   => $c->stash('layout'),
      content  => $content
    );
  }

  sub SpectrumFormatting ($self, $html_content) {
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

};
1;
__END__
# ABSTRACT: Provides rendering of Markdown to HTML for App::Schierer::HPFan
