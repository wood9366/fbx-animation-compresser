#!/usr/bin/env perl

use warnings;
use strict;

use lib '.';
use Fbx;

my $src = shift @ARGV;

die "invalid src" unless $src and -e $src;

my $fbx = Fbx->new();

$fbx->load($src);

$fbx->save("out.fbx");
