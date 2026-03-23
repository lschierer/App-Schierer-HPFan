package App::Schierer::HPFan::Controller::MagicGlossary;
# cspell: disable

use v5.42.0;
use Mooish::Base -standard;
extends 'WebFramework::Controller::Base';

with 'WebFramework::Role::Markdown';

use YAML::XS ();
require Path::Tiny;

has glossary_dir => (
  is      => 'ro',
  default => sub { Path::Tiny::path('share/magic_glossary') },
);

has entries => (is => 'lazy');

sub _build_entries ($self) {
  my @all;

  for my $file ($self->glossary_dir->children(qr/\.yaml$/)) {
    my $data = YAML::XS::Load($file->slurp_raw);
    push @all, @$data if ref $data eq 'ARRAY';
  }

  return \@all;
}

# Build a route-slug from a title string: lowercase, preserving spaces
# to match the existing URL structure from the old markdown filenames
sub _slug ($self, $str) {
  my $s = lc $str;
  $s =~ s/_/ /g;
  return $s;
}

sub build ($self) {
  my $entries = $self->entries;
  my %seen;
  my %index_entries;  # base_path => [ { title, path } ]

  for my $entry (@$entries) {
    my $category = $entry->{category} // 'spell';
    my $base     = $category eq 'potion'
      ? '/Harrypedia/magic/potions'
      : '/Harrypedia/magic/spells';

    # Route for the title (incantation or primary name)
    my $title_slug  = $self->_slug($entry->{title});
    my $title_route = "$base/$title_slug";

    unless ($seen{$title_route}++) {
      $self->_register_entry_route($title_route, $entry);
      push @{ $index_entries{$base} },
        { title => $entry->{title}, path => $title_route, type => 'file' };
    }

    # Route for the common name if different from title
    if ($entry->{name}) {
      my $name_slug  = $self->_slug($entry->{name});
      my $name_route = "$base/$name_slug";

      unless ($seen{$name_route}++) {
        $self->_register_entry_route($name_route, $entry);
      }
    }
  }

  # Register index routes for each category
  for my $base (sort keys %index_entries) {
    my @sorted = sort { $a->{title} cmp $b->{title} } @{ $index_entries{$base} };
    $self->_register_index_route($base, \@sorted);
  }

  $self->log(info => "Registered " . scalar(keys %seen) . " MagicGlossary routes");
}

sub _register_entry_route ($self, $route, $entry) {
  $self->add_navigation_route($route, $entry->{title}, { order => 50 });

  $self->router->add(
    $route,
    {
      to => sub ($c, $ctx) {
        return $self->render_entry($ctx, $entry);
      },
      action => 'http.*',
    }
  );
}

sub _register_index_route ($self, $route, $entries) {
  my $title = $route =~ /potions/ ? 'Potions' : 'Spells';
  $self->add_navigation_route($route, $title, { order => 50 });

  $self->router->add(
    $route,
    {
      to => sub ($c, $ctx) {
        return $self->render_index($ctx, $title, $entries);
      },
      action => 'http.*',
    }
  );
}

sub render_entry ($self, $ctx, $entry) {
  my $content_html = $self->markdown_string_to_html($entry->{content});
  my $current_path = $ctx->req->path;
  my $current_year = (localtime)[5] + 1900;

  my $vars = {
    content      => $content_html,
    title        => $entry->{title},
    current_year => $current_year,
    css_files    => ['/css/navigation.css'],
    sidebar      => 1,
    nav_html     => $self->render_navigation($current_path),
    site_logo    => $self->site_logo,
  };

  return $self->template('markdown', $vars);
}

sub render_index ($self, $ctx, $title, $entries) {
  my $current_path = $ctx->req->path;
  my $current_year = (localtime)[5] + 1900;

  my $vars = {
    entries      => $entries,
    title        => $title,
    current_year => $current_year,
    css_files    => ['/css/navigation.css', '/css/directory-list.css'],
    sidebar      => 1,
    nav_html     => $self->render_navigation($current_path),
    site_logo    => $self->site_logo,
  };

  return $self->template('page/autoindex', $vars);
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Controller::MagicGlossary - Routes for spells, potions, and other magical glossary entries

=head1 DESCRIPTION

Loads YAML data from share/magic_glossary/ and generates deduplicated routes
for each entry.  Each entry may produce up to two routes: one for the title
(typically the incantation) and one for the common name if present.

=cut
