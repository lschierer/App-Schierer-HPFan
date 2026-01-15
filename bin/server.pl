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

my $mode = 'development';

GetOptions('mode=s' => \$mode,)
  or die "Error in command line arguments\n";

unless ($mode =~ /(development|test|production)/) {
  croak("mode must be one of development|test|production, not '$mode'.");
}

App::Schierer::HPFan->new(env => $mode,)->run;
