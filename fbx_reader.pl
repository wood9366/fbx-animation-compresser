#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;
use Compress::Zlib;

use feature qw / switch /;

my $src = shift @ARGV;

die "invalid src" unless $src and -e $src;

sub p_pos {
    my $pos = shift || 0;
    sprintf("%d(0x%X)", $pos, $pos);
}

sub is_end {
    my $pos = shift || 0;
    my $file_size = shift || 0;

    # 固定长度偏移
    $pos += 24;

    # 16字节对齐
    my $align = $pos % 16;
    if ($align) {
        $pos += 16 - $align;
    }

    # 固定长度偏移
    $pos += 9 * 16;

    # print p_pos($pos) ." <=> ". p_pos($file_size), "\n";

    return $pos >= $file_size;
}

sub read_unpack {
    my $fh = shift;
    my $template = shift || "";
    my $size = shift || 0;

    die "read unpack invalid fh" unless $fh;

    return () unless $template ne "" and $size > 0;
    # return () unless tell($fh) + $size <= $file_size;

    read $fh, my ($buffer), $size;

    return unpack $template, $buffer;
}

# Y: 2 byte signed Integer
# C: 1 bit boolean (1: true, 0: false) encoded as the LSB of a 1 Byte value.
# I: 4 byte signed Integer
# F: 4 byte single-precision IEEE 754 number
# D: 8 byte double-precision IEEE 754 number
# L: 8 byte signed Integer
#
# f: Array of 4 byte single-precision IEEE 754 number
# d: Array of 8 byte double-precision IEEE 754 number
# l: Array of 8 byte signed Integer
# i: Array of 4 byte signed Integer
# b: Array of 1 byte Booleans (always 0 or 1)
#
#   4	Uint32	ArrayLength
#   4	Uint32	Encoding
#   4	Uint32	CompressedLength
#   ?	?	Contents
#
# S: String
# R: raw binary data
# 
#   4	Uint32	Length
#   Length	byte/char	Data

sub read_prop {
    my $fh = shift;
    my $node_name = shift;
    my $idx = shift || 0;

    die "read prop with invalid fh" unless $fh;

    my $lv = () = $node_name =~ /\./g;
    my $indent = "  " x $lv;

    my $type = read_unpack($fh, "A", 1);

    print "${indent}  - [$idx] type: $type";

    given ($type) {
        when ('Y') {
            my $val = read_unpack($fh, "s", 2);
            print ", value: $val\n";
            return { type => $type, val => $val + 0 };
        }

        when ('C') {
            my $val = read_unpack($fh, "C", 1);
            print ", value: ".($val ? "true" : "false");
            return { type => $type, val => $val + 0 };
        }

        when ('I') {
            my $val = read_unpack($fh, "l", 4);
            print ", value: $val\n";
            return { type => $type, val => $val + 0 };
        }

        when ('F') {
            my $val = read_unpack($fh, "f", 4);
            print ", value: $val\n";
            return { type => $type, val => $val + 0 };
        }

        when ('D') {
            my $val = read_unpack($fh, "d", 8);
            print ", value: $val\n";
            return { type => $type, val => $val + 0 };
        }

        when ('L') {
            my $val = read_unpack($fh, "q", 8);
            print ", value: $val\n";
            return { type => $type, val => $val + 0 };
        }

        when (/S|R/) {
            my $size = read_unpack($fh, "L", 4);

            my $data;

            if ($_ eq 'S') {
                $data = read_unpack($fh, "a".$size, $size);
            } elsif ($_ eq 'R') {
                read $fh, $data, $size;
            }

            $data ||= "";

            print ", size: $size, data: $data\n";
            return { type => $type, size => $size, val => $data };
        }

        when (/f|d|l|i|b/) {
            my $type = $_;
            my ($len, $enc, $size) = read_unpack($fh, "LLL", 12);

            print ", len: $len, end: $enc, size: $size\n";

            if ($enc == 1) {
                read $fh, my ($data), $size;

                # todo, decompress with unzip
                return {
                    type => $type,
                    len => $len,
                    enc => $enc,
                    size => $size,
                    val => $data,
                };
            } else {
                my @props = ();

                foreach my $idx (0 .. $len - 1) {
                    given ($type) {
                        when ('f') {
                            my $val = read_unpack($fh, "f", 4);
                            print "${indent}    - [$idx] $val\n";
                            push @props, $val + 0;
                        }

                        when ('d') {
                            my $val = read_unpack($fh, "d", 8);
                            print "${indent}    - [$idx] $val\n";
                            push @props, $val + 0;
                        }

                        when ('l') {
                            my $val = read_unpack($fh, "q", 8);
                            print "${indent}    - [$idx] $val\n";
                            push @props, $val + 0;
                        }

                        when ('i') {
                            my $val = read_unpack($fh, "l", 4);
                            print "${indent}    - [$idx] $val\n";
                            push @props, $val + 0;
                        }

                        when ('b') {
                            my $val = read_unpack($fh, "C", 1);
                            print "${indent}    - [$idx] $val\n";
                            push @props, $val + 0;
                        }

                        default {
                            print "${indent}    - [$idx] x\n";
                            push @props, "";
                        }
                    }
                }

                return {
                    type => $type,
                    len => $len,
                    enc => $enc,
                    size => $size,
                    val => \@props,
                };
            }
        }

        default {
            print "\n";
        }
    }

    return { type => $type };
}

# 4	Uint32	EndOffset
# 4	Uint32	NumProperties
# 4	Uint32	PropertyListLen
# 1	Uint8t	NameLen
# NameLen	char	Name
# ?	?	Property[n], for n in 0:PropertyListLen
# Optional		
# ?	?	NestedList
# 13	uint8[]	NULL-record
sub read_node {
    my $fh = shift;
    my $parent = shift || "";

    die "read node with invalid fh" unless $fh;

    my ($end, $num_props, $len_props, $len_name) = read_unpack($fh, "L L L C", 13);
    my $name = read_unpack($fh, "A".$len_name, $len_name) || "";

    my $node_name = $parent ? "$parent.$name" : $name;

    my $lv = () = $node_name =~ /\./g;
    my $indent = "  " x $lv;

    print "${indent}> $node_name($len_name), end: ".p_pos($end).", num props: $num_props, len props: $len_props\n";

    # my $before_prop_pos = tell $fh;

    my @props = ();

    for (0 .. $num_props - 1) {
        push @props, read_prop($fh, $node_name, $_);
    }

    # my $after_prop_pos = tell $fh;
    # print p_pos($before_prop_pos)." + $len_props -> ".p_pos($after_prop_pos)."(".p_pos($end).")\n";
    # die "read props error\n" unless $before_prop_pos + $len_props == $after_prop_pos;

    my $pos = tell $fh;

    # print "${indent}- content end, pos: ".p_pos($pos)."\n";

    my @nodes = ();

    if ($pos + 13 < $end) {
        print "${indent}- nested nodes, pos: ".p_pos($pos)."\n";
        # is end of node
        while ($pos + 13 < $end) {
            # has nested nodes
            push @nodes, read_node($fh, $node_name);
            $pos = tell $fh;
        }

        seek $fh, 13, 1;
    }

    print "${indent}< $node_name, ".p_pos(tell $fh)."\n";

    return {
        end => $end,
        num_props => $num_props,
        len_props => $len_props,
        name => $name,
        props => \@props,
        nodes => \@nodes,
    };
}

my $file_size = -s $src;

open my $fh, "<:raw", $src;

# read fbx head
my ($mark, $reverse0, $reverse1, $version) = read_unpack($fh, "A21 h2 h2 I", 27);

unless ($mark eq 'Kaydara FBX Binary') {
    print "no FBX\n";
    exit 0;
}

print "FBX version: $version, size: $file_size\n";

# read fbx nodes
my $pos = tell $fh;

my @nodes = ();

while (not is_end($pos, $file_size)) {
    push @nodes, read_node($fh);
    $pos = tell $fh;
}

close $fh;

print Dumper(\@nodes);
