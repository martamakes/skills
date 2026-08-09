#!/usr/bin/perl

use warnings;
use strict;
use autodie;

sub timestamp_to_seconds {
    my ($ts) = @_;
    if ($ts =~ /^(\d+):(\d+):(\d+)(?:\.\d+)?$/) {
        return $1 * 3600 + $2 * 60 + $3;
    }
    die "Invalid timestamp format: $ts";
}

sub parse_vtt {
    my ($vtt_path) = @_;
    open(my $fh, "<", $vtt_path);
    my $timestamp_seen = 0;
    my $this_start = 0;
    my $last_text_line = '';
    my @moments;
    while (my $line = <$fh>) {
        chomp $line;
        if (!$timestamp_seen) {
            if ($line =~ /^\d\d:\d\d/) {
                $timestamp_seen = 1;
            } else {
                next;
            }
        }
        next if $line =~ /^\s*$/;
        next if $line =~ /<\/c>$/;
        if ($line =~ /(\d\d:\d\d:\d\d\.\d\d\d) --> (\d\d:\d\d:\d\d\.\d\d\d)/) {
            $this_start = $1;
            next;
        }
        next if $line eq $last_text_line;
        push @moments, { timestamp => $this_start, text => $line };
        $last_text_line = $line;
    }
    close $fh;
    return @moments;
}

sub run {
}

run() unless caller();
1;
