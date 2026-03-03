package App::Schierer::HPFan::Controller::Root;
# cspell: disable

use v5.42.0;
use utf8::all;
use Mooish::Base -standard;
with 'App::Schierer::HPFan::Role::Gramps';
with 'WebFramework::Role::Markdown';
with 'App::Schierer::HPFan::Role::YAMLTables';
with 'App::Schierer::HPFan::Role::CannonQuote';
extends 'WebFramework::Controller::Base';

use Future::AsyncAwait;
require Path::Tiny;
require Path::Iterator::Rule;
require PAGI::App::File;


has app_config => (
  is      => 'ro',
  default => sub {
    my $self = shift;
    return $self->app->config;
  },
);

has base_dir => (
  is      => 'ro',
  default => sub {
    my $self = shift;
    return Path::Tiny::path($self->app->config->{config}->{markdown_dir});
  },
);

sub build ($self) {
  my $build_start = sprintf('build method for "%s"', __PACKAGE__);
  $self->logger->info($build_start);
  my $tree   = $self->_build_Root_Tree;
  my @routes = sort keys %$tree;

  # Register all routes
  for my $route (@routes) {
    my $entry = $tree->{$route};

    # Add to navigation
    if ($route eq '/Harrypedia') {
      $self->add_navigation_route($route, $entry->{title}, { order => 10 });
    }
    elsif (defined($entry->{order})) {
      $self->add_navigation_route($route, $entry->{title},
        { order => $entry->{order} });
    }
    else {
      $self->add_navigation_route($route, $entry->{title}, { order => 50 });
    }

    $self->router->add(
      $route,
      {
        to => async sub ($c, $ctx) {
          return await $self->page_handler($ctx, $route, $entry);
        },
        action => 'http.*',
      }
    );
  }

  my $static_count = 0;
  my $extensions = qr/\.(?:pdf|epub|azw3)$/;
  my $sarule = Path::Iterator::Rule->new->file->name( $extensions );
  my $saiter = $sarule->iter( $self->base_dir);

  my %mime_types = (
    pdf  => 'application/pdf',
    epub => 'application/epub+zip',
    azw3 => 'application/vnd.amazon.ebook',
  );

  while ( defined( my $file = $saiter->() )) {
    $file = Path::Tiny::path($file);
    $static_count++;
    my $path = $file->relative($self->base_dir);
    my $route = sprintf('/%s', $path );
    $route =~ s{//}{/};
    my ($ext) = $file->basename =~ /\.([^.]+)$/;
    my $mime = $mime_types{$ext} // 'application/octet-stream';
    $self->logger->info("mime type for $file is $mime");
    
    my $no_sitemap = ($ext ne 'pdf');
    $self->add_navigation_route($route, $path->basename( $extensions ), { order => 50, no_sitemap => $no_sitemap });
    $self->router->add($route, 
      {
        to => sub ($c, $ctx) {
          $ctx->res->content_type($mime);
          $ctx->res->send_raw($file->slurp_raw);
          return $ctx->res;
        },
        action => 'http.get',
      }
    );
  }


  $self->logger->info("Registered " . (scalar(@routes) + $static_count) . " Root routes");

  # Add catch-all route for directory gaps (AutoIndex)
  $self->router->add(
    '/*path',
    {
      to => sub ($self, $ctx, @args) {
        return $self->handle_directory_gap($ctx);
      },
      action => 'http.*',
    }
  );
}

async sub page_handler ($self, $ctx, $route, $entry) {
  my $fm       = $self->parse_markdown_frontmatter($entry->{path});
  my $title    = $fm->{title};
  my $template = $fm->{template} // 'markdown.tt';

  if (!$title) {
    my $path_for_title = $entry->{route};
    $path_for_title =~ s|^/||;
    $title = $path_for_title;
    $title =~ s|/| - |g;
    $title =~ s/[-_]/ /g;
    $title =~ s/\b(\w)/\U$1/g;
  }

  my $current_year = (localtime)[5] + 1900;
  my $sidebar      = $fm->{layout} // 1;
  $sidebar = 0 if ($sidebar =~ /splash/);

  my $raw_content      = Path::Tiny::path($entry->{path})->slurp_utf8;
  my $has_classlist    = $raw_content =~ /classlisttable/i;
  my $has_yamltable    = $raw_content =~ /yamltable/i;
  my $has_cannon_quote = $raw_content =~ /cannon-quote/i;

  my $vars = {};
  $template =
      exists $fm->{template}          ? $fm->{template}
    : exists $fm->{template_override} ? $fm->{template_override}
    :                                   $template;
  $vars->{template_override} = $template;

  if (exists $fm->{autoindex} && !!$fm->{autoindex}) {
    my $autoindex =
        $entry->{path}->is_dir
      ? $self->generate_directory_index($entry->{path})
      : $self->generate_directory_index($entry->{path}->parent);

    push @{ $vars->{css_files} }, '/css/directory-list.css';
    $vars->{entries} = $autoindex;
  }

  if ($has_classlist) {
    my $html = $self->retrieve_rendered_markdown($entry->{path});
    $html = await $self->render_classlist_tables($html);
    $html = $self->process_cannon_quotes($html) if $has_cannon_quote;

    $vars = {
      $vars->%*,
      content      => $html,
      title        => $title,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/classlist.css'],
      sidebar      => $sidebar,
      nav_html     => $self->render_navigation($entry->{route}),
    };

    return $self->template($template, $vars);
  }

  if ($has_yamltable) {
    my $html = $self->retrieve_rendered_markdown($entry->{path});
    $html = await $self->render_yaml_tables($html, $entry);
    $html = $self->process_cannon_quotes($html) if $has_cannon_quote;

    $vars = {
      $vars->%*,
      content      => $html,
      title        => $title,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/yamltable.css'],
      sidebar      => $sidebar,
      nav_html     => $self->render_navigation($entry->{route}),
    };

    return $self->template($template, $vars);
  }

  if ($has_cannon_quote) {
    my $html = $self->retrieve_rendered_markdown($entry->{path});
    $html = $self->process_cannon_quotes($html);

    $vars = {
      $vars->%*,
      content      => $html,
      title        => $title,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/cannon-quote.css'],
      sidebar      => $sidebar,
      nav_html     => $self->render_navigation($entry->{route}),
    };

    return $self->template($template, $vars);
  }

  return $self->render_markdown_page(
    $entry->{path},
    $entry->{route},
    {
      $vars->%*,
      site_logo => $self->site_logo(),
      title     => $title,
      sidebar   => $sidebar,
      nav_html  => $self->render_navigation($entry->{route}),
    }
  );

}

sub handle_directory_gap ($self, $ctx) {
  my $path = $ctx->req->path;
  $path =~ s|^/||;    # Remove leading slash

  my $dir_path = $self->base_dir->child($path);

  # Check if this is a directory without index.md but has children
  if ( $dir_path->is_dir
    && $dir_path->children
    && !$dir_path->child('index.md')->exists) {
    my $entries = $self->generate_directory_index($dir_path);

    # Generate title from path
    my $title = $path || 'Home';
    $title =~ s|/| - |g;
    $title =~ s/[-_]/ /g;
    $title =~ s/\b(\w)/\U$1/g;

    my $current_year    = (localtime)[5] + 1900;
    my $navigation_html = $self->render_navigation($ctx->req->path);

    my $vars = {
      entries      => $entries,
      title        => $title,
      current_year => $current_year,
      css_files    => ['/css/navigation.css', '/css/directory-list.css',],
      sidebar      => 1,
      nav_html     => $navigation_html,
      site_logo    => $self->site_logo(),
    };

    return $self->template('page/autoindex.tt', $vars);
  }

  # Not found - set status and render error template
  $ctx->res->status(404);
  return $self->template(
    'error.tt',
    {
      title        => '404 - Page Not Found',
      message      => 'The requested page was not found.',
      current_year => (localtime)[5] + 1900,
    }
  );
}

sub _build_Root_Tree ($self) {
  my %tree;

  $self->logger->debug(sprintf('about to iterate over "%s"', $self->base_dir));
  my $rule = Path::Iterator::Rule->new;
  my $next = $rule->file->nonempty->name(qr/\.md/)->iter(
    $self->base_dir,
    {
      depthfirst      => -1,
      follow_symlinks =>  0,
      report_symlinks =>  0,
      sorted          =>  1,
    }
  );
  while (defined(my $file = $next->())) {
    $file = Path::Tiny::path($file);
    $self->logger->debug("Root Controller iterating over '$file'");

    # Fast frontmatter parsing - only read first 20 lines
    my $fm = $self->parse_markdown_frontmatter($file->absolute);
    unless ($fm) {
      $self->logger->warn("No frontmatter available for '$file'");
      next;
    }
    unless (ref($fm) eq 'HASH' && keys %$fm) {
      $self->logger->warn("Empty frontmatter for '$file'");
      next;
    }
    my $title = $fm->{title} // $file->basename(qr/.md/);
    my $route;
    my $order;

    if ($title =~ /index/) {
      $title = $file->parent->basename;
      my $rel_dir = $file->parent->relative($self->base_dir);
      if ($rel_dir eq '.') {
        # Root bookmarks directory
        $route = '/';
      }
      else {
        $route = "/$rel_dir";
      }
    }
    else {
      $route = $file->relative($self->base_dir)->stringify;
      $route =~ s/(.+)\.md$/\/$1/;
      $route =~ s/\/index$//;
    }

    $tree{$route} = {
      title => $title,
      path  => $file,
      route => $route,
    };

    if (ref($fm->{sidebar})) {
      if (exists $fm->{sidebar}->{order}) {
        $self->logger->debug(sprintf(
          'found order %s for file "%s"',
          $fm->{sidebar}->{order}, $file
        ));
        $tree{$route}->{order} = $fm->{sidebar}->{order};
      }
    }

    $self->logger->debug(
      sprintf('Registering route "%s" for file "%s"', $route, $file));
  }
  return \%tree;
}

1;
  __END__
