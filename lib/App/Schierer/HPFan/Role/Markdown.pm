
package App::Schierer::HPFan::Role::Markdown;
  use Mojo::Base -role, -signatures;
  use v5.42.0;
  use utf8::all;
  use experimental qw(class);
  require Pandoc;
  require Scalar::Util;
  require YAML::PP;
  require Mojo::DOM58;

  my $customCommonMark = join('+',
    qw(commonmark alerts attributes autolink_bare_uris footnotes implicit_header_references pipe_tables raw_html rebase_relative_paths smart gfm_auto_identifiers)
  );

  sub render_markdown_file ($self, $file_path, $opts = {}) {
    $opts //= {};

    unless ($file_path && $file_path->isa('Mojo::File')) {
      $self->logger->error("file_path must be a 'Mojo::File' not "
          . (ref($file_path) || 'undefined'));
      return $self->reply->not_found;
    }

    my $parsedFile = $self->parse_markdown_frontmatter($file_path);
    unless ($parsedFile) {
      $self->logger->error("error parsing front matter for $file_path");
      return $self->reply->not_found;
    }

    foreach my $key (keys %{ $parsedFile->{front_matter} }) {
      $self->stash($key => $parsedFile->{front_matter}->{$key})
        unless exists $self->stash->{$key};
    }

    $self->stash(title => $parsedFile->{title}) unless exists $self->stash->{title};

    my $layout = $parsedFile->{front_matter}->{layout} // 'default';
    if ($layout =~ /splash/i) {
      $self->stash(sidebar => 0);
    }
    $layout = 'default';
    $self->stash(layout => $layout) unless exists $self->stash->{layout};

    my $template = $opts->{template} // $self->stash('template') // 'markdown';

    my $parser = Pandoc->new();
    my $html_content = $parser->convert(
      $customCommonMark => 'html5',
      $parsedFile->{content}
    );

    $html_content = $self->spectrum_formatting($html_content);
    my $content = $self->stash('content') // $html_content;

    if (!exists $self->stash->{markdown_content}) {
      $self->stash(markdown_content => $html_content);
    }

    if ((
        $self->stash('front_matter')
        && exists $self->stash('front_matter')->{autoindex}
      )
      or $self->stash('autoindex')
    ) {
      my $directory       = $file_path->dirname;
      my $generated_index = $self->app->generate_directory_index($directory);
      $self->stash(generated_index => $generated_index);
    }

    return $self->render(
      template => $template,
      layout   => $layout,
      content  => $content
    );
  }

  sub render_markdown_snippet ($self, $snippet) {

    if (not defined $snippet or length($snippet) == 0) {
      $self->logger->warn('snippet must be present!!');
      return '';
    }

    my $parser = Pandoc->new();
    my $html_content = $parser->convert(
      $customCommonMark => 'html5',
      $snippet
    );
    return $self->spectrum_formatting($html_content);
  }

  sub parse_markdown_frontmatter ($self, $file_path) {

    unless ($file_path && $file_path->isa('Mojo::File')) {
      $self->logger->error("file_path must be a 'Mojo::File' not "
          . (ref($file_path) || 'undefined'));
      return 0;
    }

    unless (-f $file_path) {
      unless ((!-d $file_path) || (!-f $file_path->child('index.md'))) {
        $self->logger->error("Markdown file not found: $file_path");
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
        $self->logger->error("Error parsing YAML front matter: $@");
      }
      elsif (ref $front_matter eq 'HASH') {
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

  sub spectrum_formatting ($self, $html_content) {
    my $dom = Mojo::DOM58->new($html_content);

    my %spectrum_h = (
      h1 => "spectrum-Heading spectrum-Heading--sizeXXL",
      h2 => "spectrum-Heading spectrum-Heading--sizeXL",
      h3 => "spectrum-Heading spectrum-Heading--sizeL",
      h4 => "spectrum-Heading spectrum-Heading--sizeM",
      h5 => "spectrum-Heading spectrum-Heading--sizeS",
      h6 => "spectrum-Heading spectrum-Heading--sizeXS",
    );

    for my $tag (keys %spectrum_h) {
      $dom->find($tag)->each(sub { $_->attr(class => $spectrum_h{$tag}) });
    }

    $dom->find('p')->each(sub {
      $_->attr(
        class => "spectrum-Body spectrum-Body--serif spectrum-Body--sizeM");
    });

    $dom->find('li')->each(sub {
      $_->attr(
        class => "spectrum-Body spectrum-Body--serif spectrum-Body--sizeM");
    });

    $dom->find('a')->each(sub {
      $_->attr(
        class => "spectrum-Link spectrum-Link--primary spectrum-Link--quiet");
    });

    $dom->find('em')->each(sub {
      $_->attr(class => "spectrum-Body-emphasized");
    });

    $dom->find('strong')->each(sub {
      $_->attr(class => "spectrum-Body-strong");
    });

    $dom->find('hr')->each(sub {
      $_->attr(class => 'spectrum-Divider spectrum-Divider--sizeM');
    });

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

    return $dom->to_string;
  }

1;
__END__
# ABSTRACT: Role providing markdown rendering methods
