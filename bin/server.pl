#!/usr/bin/env perl
use v5.42.0;
use utf8::all;
use lib 'lib';
use lib '../PAGI-WebServer/lib';
require App::Schierer::HPFan;
require PAGI::Server;
use Future::AsyncAwait;
use Getopt::Long;
use Carp;

my $config_file = 'config.yml';
my $mode        = 'development';

GetOptions(
  'config=s' => \$config_file,
  'mode=s'   => \$mode,
) or die "Error in command line arguments\n";

unless ($mode =~ /(development|test|production)/) {
  croak("mode must be one of development|test|production, not '$mode'.");
}

my $config_dir   = 'share/conf';
my $local_config = App::Schierer::HPFan->getConfig($mode, $config_dir);

App::Schierer::HPFan->new(
  initial_config => $local_config,
  env            => $mode,
)->run;
