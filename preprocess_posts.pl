#!/usr/bin/perl

use strict;
use warnings;
use open OUT => ':utf8';

use Getopt::Std;
use XML::Simple;
use HTML::Strip;
use HTML::Entities;

use Data::Dumper;

open(my $fh, '<', 'stackoverflow_data/stackoverflow.com-Posts')
    or die "Unable to open file, $!";

my $hs = HTML::Strip->new(
    # striptags   => [ 'code' ],
);
my $wfhs = {};

my $year_counts = {'2008' => 0, '2009' => 0, '2010' => 0, '2011' => 0, '2012' => 0, '2013' => 0, '2014' => 0, };
    
my $row_count = 0;
while (<$fh>) {
    my $line = $_;
    $line = trim($line);
    
    if($line =~ m/<row/) {
        my $row = XMLin($line);
        my $date = $row->{CreationDate};
        my $year = substr($date, 0, 4);
        my $body = $row->{Body};
        
        # process the body
        ## extract code fragments
        my @code_fragments = ($body =~ /<code>(.+?)<\/code>/sg);
        $body =~ s/<code>(.+?)<\/code>//sg;
        
        $body = decode_entities($body);
        $body = $hs->parse($body);
        $hs->eof();
        
        # clean up the row
        $row->{Body} = $body;
        $row->{Body} =~ tr{\n\r}{ };
        
        $row->{Code} = join(' ', @code_fragments);
        $row->{Code} =~ tr{\n\r}{ };
        
        if(defined $row->{Tags}) {
            my @tags = ($row->{Tags} =~ m/<(.+?)>/g);
            $row->{Tags} = join(';', @tags);
        }
        
        # write out the data elsewhere
        my $wfh = $wfhs->{$year};
        
        if(!defined $wfh) {
            $wfh = getWriteHandle("stackoverflow_data/posts/$year");
            $wfhs->{$year} = $wfh;
        }
        
        $line = XMLout($row, RootName => 'row');
        print $wfh "$line";
        
        $year_counts->{$year}++;
        $row_count++;
    }
}

warn Dumper "Total rows: $row_count";
warn Dumper $year_counts;

sub getWriteHandle
{
    my $filepath = shift;
    open(my $wfh, '>', $filepath)
        or die "Unable to open file, $!";
    
    return $wfh;
}

sub trim
{
    my $string = shift;
    $string =~ s/^\s+|\s+$//g;
    
    return $string;
}
