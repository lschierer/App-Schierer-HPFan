package App::Schierer::HPFan::Bookmarks;

use v5.42.0;
use strict;
use warnings;
use Moo;
use Path::Tiny;
use YAML::XS qw(Load);
use Log::Log4perl qw(get_logger);
use Encode qw(encode_utf8);
use Future::AsyncAwait;

has template => (
    is => 'ro',
    required => 1,
);

has navigation => (
    is => 'ro',
    required => 1,
);

has markdown => (
    is => 'ro',
    required => 1,
);

has site_logo => (
    is      => 'ro',
    default => '',
);

has bookmarks_dir => (
    is => 'ro',
    default => sub { path('share/Bookmarks') },
);

has bookmarks_tree => (
    is => 'lazy',
);

sub _build_bookmarks_tree {
    my ($self) = @_;

    my $logger = get_logger(__PACKAGE__);
    my %tree;

    my $iter = $self->bookmarks_dir->iterator({
        recurse => 1,
        follow_symlinks => 0,
    });

    while (my $file = $iter->()) {
        next unless $file->is_file && $file->basename =~ /\.yaml$/;

        $self->process_bookmark_file($file, \%tree);
    }

    my @keys = sort keys %tree;
    $logger->debug("Built bookmarks tree with " . scalar(@keys) . " entries");

    return \%tree;
}

sub process_bookmark_file {
    my ($self, $file, $tree) = @_;

    my $logger = get_logger(__PACKAGE__);
    $logger->debug("Processing bookmark file: $file");

    my $content;
    eval {
        my $yaml_str = $file->slurp_utf8;
        $content = Load($yaml_str);
    };
    if ($@) {
        $logger->error("Error parsing YAML file '$file': $@");
        return;
    }

    unless (ref $content eq 'HASH') {
        $logger->warn("Content is not a hash in '$file': " . ref($content));
        return;
    }

    unless ($content->{name}) {
        $logger->warn("'name' is required in '$file', ignoring");
        return;
    }

    # Determine title (use 'title' if present, otherwise 'name')
    my $title = $content->{title} // $content->{name};

    # Calculate route path
    my $rel_path = $file->relative($self->bookmarks_dir);
    my $route;

    if ($file->basename eq 'index.yaml') {
        # For index.yaml, route is the directory path
        my $rel_dir = $file->parent->relative($self->bookmarks_dir);
        if ($rel_dir eq '.') {
            # Root bookmarks directory
            $route = '/Bookmarks';
        }
        else {
            $route = "/Bookmarks/$rel_dir";
        }
    }
    else {
        # For regular files, route includes the name from YAML
        my $dir_path = $file->parent->relative($self->bookmarks_dir);
        if ($content->{name} eq 'Bookmarks') {
            $route = '/Bookmarks';
        }
        else {
            $route = $dir_path eq '.'
                ? "/Bookmarks/$content->{name}"
                : "/Bookmarks/$dir_path/$content->{name}";
        }
    }

    $logger->debug("Route for '$file' is '$route' with title '$title'");

    $tree->{$route} = {
        %$content,
        title => $title,
        path => $file,
        route => $route,
    };
}

async sub register_routes {
    my ($self, $nav, $router) = @_;

    my $logger = get_logger(__PACKAGE__);
    my $tree = $self->bookmarks_tree;
    my @routes = sort keys %$tree;

    # Register all routes
    for my $route (@routes) {
        my $entry = $tree->{$route};

        # Add to navigation
        $nav->add_route($route, $entry->{title}, { order => 10 });

        # Determine if this is an index or page route
        if ($entry->{path}->basename eq 'index.yaml') {
            # Index route - shows list of children
            $router->get($route => async sub {
                my ($scope, $receive, $send) = @_;
                await $self->bookmark_index_handler($scope, $receive, $send, $entry, \@routes);
            });
        }
        else {
            # Page route - shows bookmark items
            $router->get($route => async sub {
                my ($scope, $receive, $send) = @_;
                await $self->bookmark_page_handler($scope, $receive, $send, $entry);
            });
        }
    }

    $logger->info("Registered " . scalar(@routes) . " bookmark routes");
}

async sub bookmark_index_handler {
    my ($self, $scope, $receive, $send, $entry, $all_routes) = @_;

    my $logger = get_logger(__PACKAGE__);
    my $current_path = $scope->{path};

    # Find direct children of current path
    my @child_entries;
    my $tree = $self->bookmarks_tree;

    for my $route (@$all_routes) {
        next unless $route =~ /^\Q$current_path\E/;
        next if $route eq $current_path;  # Skip self

        # Get relative path
        my $relative = $route;
        $relative =~ s/^\Q$current_path\E\/?//;

        # Skip grandchildren (has more path segments)
        next if $relative =~ m{/};

        # This is a direct child
        my $entry_data = $tree->{$route};
        push @child_entries, {
            title => $entry_data->{title} // $entry_data->{name},
            path => $route,
        };
    }

    @child_entries = sort { $a->{title} cmp $b->{title} } @child_entries;

    # Render comments as markdown if present
    my $comments_html = '';
    if ($entry->{comments}) {
        $comments_html = $self->markdown->pd->convert('markdown' => 'html', $entry->{comments});
    }

    my $current_year = (localtime)[5] + 1900;
    my $navigation_html = $self->navigation->render($current_path);

    my $vars = {
        items => \@child_entries,
        comments => $comments_html,
        title => $entry->{title},
        current_year => $current_year,
        css_files => ['/css/navigation.css', '/css/directory-list.css'],
        sidebar => 1,
        navigation => $navigation_html,
        site_logo => $self->site_logo,
    };

    my $html = $self->template->render(
        'bookmarks/index.tt',
        $vars,
        { layout => 'layouts/default.tt' }
    );

    my $bytes = encode_utf8($html);

    await $send->({
        type => 'http.response.start',
        status => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
    });
    await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
    });
}

async sub bookmark_page_handler {
    my ($self, $scope, $receive, $send, $entry) = @_;

    my $logger = get_logger(__PACKAGE__);
    my $current_path = $scope->{path};

    # Get items array
    my @items = $entry->{items} ? @{ $entry->{items} } : ();
    @items = sort { ($a->{title}{name} // '') cmp ($b->{title}{name} // '') } @items;

    # Render top-level comments as markdown if present
    my $comments_html = '';
    if ($entry->{comments}) {
        $comments_html = $self->markdown->pd->convert('markdown' => 'html', $entry->{comments});
    }

    # Render each item's comments as markdown
    for my $item (@items) {
        if ($item->{comments}) {
            $item->{comments_html} = $self->markdown->pd->convert('markdown' => 'html', $item->{comments});
        }
    }

    my $current_year = (localtime)[5] + 1900;
    my $navigation_html = $self->navigation->render($current_path);

    my $vars = {
        items => \@items,
        comments => $comments_html,
        title => $entry->{title},
        current_year => $current_year,
        css_files => ['/css/navigation.css', '/css/bookmarks.css'],
        sidebar => 1,
        navigation => $navigation_html,
        site_logo => $self->site_logo,
    };

    my $html = $self->template->render(
        'bookmarks/page.tt',
        $vars,
        { layout => 'layouts/default.tt' }
    );

    my $bytes = encode_utf8($html);

    await $send->({
        type => 'http.response.start',
        status => 200,
        headers => [['content-type', 'text/html; charset=utf-8']],
    });
    await $send->({
        type => 'http.response.body',
        body => $bytes,
        more => 0,
    });
}

1;
