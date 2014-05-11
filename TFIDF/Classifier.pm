package TFIDF::Classifier;

#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Std;
use Text::English;

use Data::Dumper;

sub new
{
    my ($class, %args) = @_;
    
    my $self = {
        encountered_labels => {},
        encountered_tokens => {},
        stop_list => {},
        training_data => [],
    };
    
    bless $self, $class;
    
    $self->setStopList($args{stop_list});
    $self->setTrainingData($args{training_data});
    
    $self->train() if $self->{training_data};
    
    return $self;
} # new

sub setStopList
{
    my ($self, $stop_list) = @_;
    
    return unless defined $stop_list;
    
    if(ref $stop_list eq 'HASH') {
        $self->{stop_list} = $stop_list;
        return;
    }
    
    # else assume path to file containing list is specified;
    open(my $stop_list_fh, '<', $stop_list)
        or die "Unable to open file, $!";
    
    while(my $word = <$stop_list_fh>) {
        chomp($word);
        $word = (Text::English::stem($word))[0];
        
        $self->{stop_list}->{$word} = 1;
    }
    
    return;
} # setStopList

sub setTrainingData
{
    my ($self, $training_data) = @_;
    
    return if !$training_data;
    
    $self->{training_data} = $training_data;
    
    return;
} # setTrainingData

sub train
{
    my $self = shift;
    my $training_data = shift;
    
    $training_data = $self->{training_data} if !$training_data;
    
    return if !$training_data;
    
    
} # train

sub classify
{
    my ($self, $testing_data, $opts) = @_;
    
    my @assigned_labels;
    
    foreach my $sample (@$testing_data) {
        push(@assigned_labels, $self->_classifySample($sample, $opts));
    }
    
    return \@assigned_labels;
} # classify

sub _classifySample
{
    my ($self, $sample, $opts) = @_;
    
    
    if($opts->{return_multiple_classifications}) {
        my $desired_amount = $opts->{return_multiple_classifications};
        return [@most_likely_classifcations[0..$desired_amount-1]];
    }
    
    return $most_likely_classifcations[0];
}

## _clean
# pass through porter stemmer
# confirm they are not on the stop list
sub _clean
{
    my ($self, $tokens) = @_;
    
    my @clean_tokens;
    @$tokens = Text::English::stem(@$tokens);
    
    foreach my $token (@$tokens) {
        ## Add any further token transformations here
        next if (length($token) < 2);
        
        $token = lc($token);
        
        push(@clean_tokens, $token) if !$self->{stop_list}->{$token};
    }
    
    return \@clean_tokens;
}

return 1;
