#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Getopt::Std;
use XML::Simple;
use HTML::Entities;

use Text::English;
use TFIDF::Classifier;

use constant STOPLISTLOC => 'english.stop';

our ($opt_h, $opt_i, $opt_r, $opt_t);
getopts('hi:r:t:');

if($opt_h || !$opt_i) {
	help();
}

my $input_file = $opt_i;
my $training_count = $opt_r || 1000;
my $testing_count = $opt_t || 100;

my $tag_list = {};

my (@training_data, @testing_data);

open(my $fh, '<', $input_file) or die "Unable to open file, $!";

while (<$fh>) {
    my $row_xml_str = $_;
    my $row = XMLin($row_xml_str);
    
    next if !defined $row->{Tags};
    
    my $sample = {
        labels => [split(';', $row->{Tags})],
        tokens => [split(m/[^\w]/, $row->{Code} . $row->{Body})] # features
    };
    
    if(scalar @training_data >= $training_count) {
        my $encountered_sample_tags = 1;
        
        foreach my $tag (@{$sample->{labels}}) {
            if(!defined $tag_list->{$tag}) {
                $encountered_sample_tags = 0;
                last;
            }
        }
        
        push(@testing_data, $sample) if $encountered_sample_tags;
    }
    else {
        foreach my $tag (@{$sample->{labels}}) {
            $tag_list->{$tag} = 1;
        }
        
        push(@training_data, $sample);
    }
    
    last if scalar @testing_data == $testing_count;
}

print "Finished compiling a training and testing set...\n";

my $classifier = TFIDF::Classifier->new(
    stop_list => STOPLISTLOC,
    training_data => \@training_data,
);
print "Finished training a NB classifier...\n";

my $stime = time();
my $classifications = $classifier->classify(\@testing_data, {return_multiple_classifications => 5});
my $etime = time();
my $runtime = $etime - $stime;

print "Finished classifying the testing set ($runtime seconds)...\n";


my ($total_tags, $predicted_tags) = (0, 0); # figure out accuracy
my $cl_idx = 0;

foreach my $sample (@testing_data) {
    my %tags_for_sample = map {$_ => 1} @{$sample->{labels}};
    my @valid_classifications = grep {$tags_for_sample{$_}} @{$classifications->[$cl_idx]};
    
    $predicted_tags += scalar @valid_classifications;
    $total_tags += scalar @{$sample->{labels}};
    $cl_idx++;
}

print "# of correct predictions = $predicted_tags\n";
print "# of tags to predict = $total_tags\n";

sub help
{
	die 'Usage: ./nbclassify.pl -i input_file [-r # of training samples to use] [-t # of testing samples to use]';
}
