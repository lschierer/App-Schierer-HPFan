#!/usr/bin/env perl
use v5.42.0;
use utf8::all;
use Encode qw(encode_utf8);
use lib '../PAGI-WebServer/lib';
use PAGI::WebServer;
use PAGI::WebServer::Router;
use PAGI::WebServer::Markdown;
use PAGI::Server;
use Future::AsyncAwait;
use Path::Tiny;

my $framework = PAGI::WebServer->new(
    config_file => 'config.yml'
);

$framework->setup_logging;

my $markdown = PAGI::WebServer::Markdown->new;
my $pages_dir = path('share/pages');

# Create router
my $router = PAGI::WebServer::Router->new;

# Add route for root
$router->get('/' => async sub {
    my ($scope, $receive, $send) = @_;

    my $index_file = $pages_dir->child('index.md');
    if ($index_file->exists) {
        my $html = $markdown->render($index_file->stringify);
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
    } else {
        await $send->({
            type => 'http.response.start',
            status => 404,
            headers => [['content-type', 'text/plain']],
        });
        await $send->({
            type => 'http.response.body',
            body => 'Not Found',
            more => 0,
        });
    }
});

# Add dynamic route for markdown files
$router->get('*' => async sub {
    my ($scope, $receive, $send) = @_;

    my $path = $scope->{path};
    $path =~ s|^/||; # Remove leading slash

    # Try exact path first
    my $md_file = $pages_dir->child("$path.md");

    # If not found, try as directory with index.md
    if (!$md_file->exists) {
        $md_file = $pages_dir->child($path, 'index.md');
    }

    if ($md_file->exists) {
        my $html = $markdown->render($md_file->stringify);
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
    } else {
        await $send->({
            type => 'http.response.start',
            status => 404,
            headers => [['content-type', 'text/plain']],
        });
        await $send->({
            type => 'http.response.body',
            body => 'Not Found',
            more => 0,
        });
    }
});

# Create and run server
my $server = PAGI::Server->new(
    app => $router->to_app,
    port => 3001,
);

$server->run;
