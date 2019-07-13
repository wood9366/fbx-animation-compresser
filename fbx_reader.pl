#!/usr/bin/env perl

use warnings;
use strict;

my $src = shift @ARGV;

die "invalid src" unless $src and -e $src;

my $file_size = -s $src;

open my $fh, "<:raw", $src;

read $fh, my $head, 27;

my ($mark, $reverse0, $reverse1, $version) = unpack("A21 h2 h2 I", $head);

unless ($mark eq 'Kaydara FBX Binary') {
    print "no FBX\n";
    exit 0;
}

print "FBX version: $version, size: $file_size\n";

sub p_pos {
    my $pos = shift || 0;
    sprintf("%d(0x%X)", $pos, $pos);
}

sub read_unpack {
    my $template = shift || "";
    my $size = shift || 0;

    return () unless $template ne "" and $size > 0;
    return () unless tell($fh) + $size <= $file_size;

    read $fh, my ($buffer), $size;

    return unpack $template, $buffer;
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

    return unless $fh;

    my ($end, $num_props, $len_props, $len_name) = read_unpack("L L L C", 13);
    my $name = read_unpack("A".$len_name, $len_name) || "";

    my $node_name = $parent ? "$parent.$name" : $name;

    # skip props
    seek $fh, $len_props, 1;

    my $pos = tell $fh;

    my $lv = () = $node_name =~ /\./g;
    my $indent = "  " x $lv;

    print "${indent}> $node_name($len_name)\n";
    print "${indent}  end: $end, num props: $num_props, len props: $len_props, pos: ".p_pos($pos)."\n";

    if ($pos + 13 < $end) {
        # is end of node
        while ($pos + 13 < $end) {
            # has nested nodes
            read_node($fh, $parent ? "$parent.$name" : $name);
            $pos = tell $fh;
        }

        seek $fh, 13, 1;
    }

    print "${indent}< $node_name, ".p_pos(tell $fh)."\n";
}

sub is_end {
    my $pos = shift || 0;

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

my $pos = tell $fh;

while (not is_end $pos) {
    read_node $fh;
    $pos = tell $fh;
}

close $fh;
