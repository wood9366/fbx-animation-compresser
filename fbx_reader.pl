#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;

use lib '.';
use Fbx;

my $src = shift @ARGV;

die "invalid src" unless $src and -e $src;

my $fbx = Fbx->new({debug => 0});

$fbx->load($src);

my $data = $fbx->data();

sub get_node {
    my $node = shift;

    if ($node->{node_name} eq 'ROOT.Objects.AnimationCurve.KeyValueFloat') {
        foreach my $prop (@{$node->{props}}) {
            $prop->{val} = [ map { sprintf("%.3f", $_) + 0 } @{$prop->{val}} ];
        }
    }

    foreach (@{$node->{nodes}}) {
        get_node($_);
    }
}

get_node $data->{node};

# sub p_node {
#     my $node = shift;

#     if ($node->{node_name} eq 'ROOT.Objects.AnimationCurve.KeyValueFloat') {
#         foreach (@{$node->{props}}) {
#             foreach (@{$_->{val}}) {
#                 print $_, "\n";
#             }
#         }
#     }

#     foreach (@{$node->{nodes}}) {
#         p_node($_);
#     }
# }

# p_node $data->{node};

# print Dumper($fbx->data());

$fbx->save($src);
