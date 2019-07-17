#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;
use Compress::Zlib;

use feature qw / switch /;

my $src = shift @ARGV;

die "invalid src" unless $src and -e $src;

my $file_size = -s $src;

sub p_pos {
    my $pos = shift || 0;
    sprintf("%d(0x%X)", $pos, $pos);
}

sub p_mem {
    my $data = shift || "";

    my $i;
    join "", map { ++$i % 16 ? "$_ " : "$_\n" }
        unpack("H2" x length($data), $data);
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

sub primary_prop_unpack_info {
    my $type = shift || "";

    given($type) {
        when ('Y') { return ("s", 2); }
        when ('C') { return ("C", 1); }
        when ('I') { return ("l", 4); }
        when ('F') { return ("f", 4); }
        when ('D') { return ("d", 8); }
        when ('L') { return ("q", 8); }
        default { die "invaid primary prop type $type" }
    }
}

sub read_primary_prop {
    my $fh = shift;
    my $type = shift;

    die "read primary prop with invalid $fh\n" unless $fh;

    return read_unpack($fh, primary_prop_unpack_info $type);
}

sub array_prop_unpack_info {
    my $type = shift || "";

    given($type) {
        when ('f') { return ("f", 4); }
        when ('d') { return ("d", 8); }
        when ('l') { return ("q", 8); }
        when ('i') { return ("l", 4); }
        when ('b') { return ("C", 1); }
        default { die "invaid array prop type $type" }
    }
}

sub read_array_prop {
    my $fh = shift;
    my $type = shift;

    die "read array prop with invalid $fh\n" unless $fh;

    return read_unpack($fh, array_prop_unpack_info $type);
}

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
        when (/Y|C|I|F|D|L/) {
            my $val = read_primary_prop($fh, $type) + 0;

            print ", val: $val\n";

            return { type => $type, val => $val };
        }

        when (/f|d|l|i|b/) {
            my $type = $_;
            my ($len, $enc, $size) = read_unpack($fh, "LLL", 12);

            print ", len: $len, end: $enc, size: $size\n";

            my @props = ();

            if ($enc == 1) {
                read $fh, my ($data), $size;

                $data = uncompress $data;

                open my $fdata, "<", \$data;
                push @props, read_array_prop($fdata, $type) foreach (0 .. $len - 1);
                close $fdata;
            } else {
                push @props, read_array_prop($fh, $type) foreach (0 .. $len - 1);
            }

            foreach (0 .. $#props) {
                print "${indent}    - [$_] $props[$_]\n";
            }

            return {
                type => $type,
                len => $len,
                enc => $enc,
                size => $size,
                val => \@props,
            };
        }

        when (/S|R/) {
            my $size = read_unpack($fh, "L", 4);

            my $data;

            read $fh, $data, $size;

            print ", size: $size, data: $data\n";

            return { type => $type, size => $size, val => $data };
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
    my $parent = shift;
    my $lv = shift || 0;

    die "read node with invalid fh" unless $fh;

    my $end;
    my $num_props = 0;
    my $len_props = 0;
    my $len_name = 0;
    my $name = "";
    my @props = ();

    my $node_name = "";
    my $indent = "  " x $lv;

    my $start_pos = tell $fh;

    if ($parent) {
        ($end, $num_props, $len_props, $len_name) = read_unpack($fh, "L L L C", 13);

        # node 13 0x00 terminal
        return undef unless $end > 0;

        read $fh, ($name), $len_name;

        $node_name = $parent ? "$parent.$name" : $name;
    } else {
        $node_name = "ROOT";
    }

    print "${indent}> $node_name($len_name), start: ".p_pos($start_pos).", end: ".p_pos($end).", num props: $num_props, len props: $len_props\n";

    for (0 .. $num_props - 1) {
        push @props, read_prop($fh, $node_name, $_);
    }

    my @nodes = ();

    my $node_end_pos = $parent ? $end : $file_size;
    my $has_magic_tail = 0;

    while (tell($fh) < $node_end_pos) {
        my $node = read_node($fh, $node_name, $lv + 1);

        if ($node) {
            push @nodes, $node;
        } else {
            $has_magic_tail = 1;
            last;
        }
    }

    my $pos = tell $fh;
    print "${indent}< $node_name, ".($has_magic_tail ? "o" : "x").", ".p_pos($pos)."\n";
    die "$node_name end pos not match\n" unless not $parent or $pos == $end;

    return {
        end => $end,
        has_magic_tail => $has_magic_tail,
        num_props => $num_props,
        len_props => $len_props,
        len_name => $len_name,
        name => $name,
        props => \@props,
        nodes => \@nodes,
    };
}

open my $fh, "<:raw", $src;

# read fbx head
# Bytes 0 - 20: Kaydara FBX Binary  \x00 (file-magic, with 2 spaces at the end, then a NULL terminator).
# Bytes 21 - 22: [0x1A, 0x00] (unknown but all observed files show these bytes).
# Bytes 23 - 26: unsigned int, the version number. 7300 for version 7.3 for example.
my ($mark, $reverse0, $reverse1, $version) = read_unpack($fh, "Z* h2 h2 I", 27);

unless ($mark eq 'Kaydara FBX Binary  ') {
    print "no FBX\n";
    exit 0;
}

print "FBX version: $version, size: $file_size\n";

# read fbx nodes
my $node = read_node $fh;

# read tail
# tail 1, fixed 16 bytes length, changed depends on file, no rules?
read $fh, my $tail_1, 16;
print "\ntail_1:\n", p_mem($tail_1), "\n";

# skip align bytes
my $align = tell($fh) % 16;
seek $fh, 16 - $align, 1 if $align;

# tail 2, fixed 9 * 16 bytes length, const
read $fh, my $tail_2, 9 * 16;
print "\ntail_2:\n", p_mem($tail_2), "\n";

close $fh;

exit 0;

open my $fh_out, ">", "out.fbx";

# write head
print $fh_out pack("Z* h2 h2 I", $mark, $reverse0, $reverse1, $version);

# write content
sub write_node {
    my $fh = shift;
    my $node = shift;

    my $is_root = $node->{len_name} == 0;

    my $end_pos = tell $fh;
    my $len_props_pos = $end_pos + 8;

    unless ($is_root) {
        print $fh pack("L L L C",
                    $node->{end},
                    $node->{num_props},
                    $node->{len_props},
                    $node->{len_name});

        print $fh $node->{name};

    }

    my $prop_start_pos = tell $fh;

    foreach my $prop (@{$node->{props}}) {
        print $fh pack("A", $prop->{type});

        given ($prop->{type}) {
            when (/Y|C|I|F|D|L/) {
                print $fh pack((primary_prop_unpack_info($prop->{type}))[0],
                            $prop->{val});
            }

            when (/f|d|l|i|b/) {
                my $data = pack((array_prop_unpack_info($prop->{type}))[0] x $prop->{len},
                                @{$prop->{val}});

                my $size = $prop->{size};

                if ($prop->{enc} == 1) {
                    $data = compress($data);
                    $size = length($data);

                    # print "compressed data size change $prop->{size} => $size\n"
                    #     unless $prop->{size} == $size;
                }

                print $fh pack("LLL",
                            $prop->{len},
                            $prop->{enc},
                            $size);

                print $fh $data;
            }

            when (/S|R/) {
                print $fh pack("L", $prop->{size});
                print $fh $prop->{val};
            }
        }
    }

    unless ($is_root) {
        my $pos = tell $fh;
        seek $fh, $len_props_pos, 0;
        print $fh pack("L", $pos - $prop_start_pos);
        seek $fh, $pos, 0;
    }

    if (@{$node->{nodes}}) {
        write_node($fh, $_) foreach @{$node->{nodes}};
    }

    print $fh ("\x00"x13) if $node->{has_magic_tail};

    unless ($is_root) {
        my $pos = tell $fh;
        seek $fh, $end_pos, 0;
        print $fh pack("L", $pos);
        seek $fh, $pos, 0;
    }
}

write_node $fh_out, $node;

# write tail
print $fh_out $tail_1;

# 16 align
$align = tell($fh_out) % 16;
print $fh_out ("\x00"x(16 - $align));

print $fh_out $tail_2;

close $fh_out;

# print Dumper(\@nodes);
