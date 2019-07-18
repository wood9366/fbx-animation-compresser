#!/usr/bin/env perl

use warnings;
use strict;

use Getopt::Long;
use Data::Dumper;

use lib '.';
use Fbx;

my $fbx_path;
my $precision = 3;
my $debug = 0;

GetOptions("fbx=s" => \$fbx_path,
           "precision=i" => \$precision,
           "debug!" => \$debug);

die "invalid fbx path" unless $fbx_path and -e $fbx_path;

$precision = 0 if $precision < 0;
$precision = 10 if $precision > 10;

print "process fbx [$fbx_path] with precision [$precision]\n";

my $fbx = Fbx->new({debug => $debug});

$fbx->load($fbx_path);

my $data = $fbx->data();

sub get_node {
    my $node = shift;

    if ($node->{node_name} eq 'ROOT.Objects.AnimationCurve.KeyValueFloat') {
        foreach my $prop (@{$node->{props}}) {
            $prop->{val} = [ map { sprintf("%.${precision}f", $_) + 0 } @{$prop->{val}} ];
        }
    }

    get_node($_) foreach @{$node->{nodes}};
}

get_node($data->{node});

$fbx->save($fbx_path);
