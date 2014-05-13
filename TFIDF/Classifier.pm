package TFIDF::Classifier;

#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Std;
use Text::English;

use Data::Dumper;

use constant KEYWORDSPERQUERY   =>  10;

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
    
    foreach my $sample (@$training_data) {
        my $clean_tokens = $self->_clean($sample->{tokens});
        my %uniq_tokens_in_sample = ();
        
        foreach my $token (@$clean_tokens) {
            $self->{encountered_tokens}->{$token} = 0
                if !$self->{encountered_tokens}->{$token};
            
            $sample->{token_stats}->{$token} = 0 
                if !$sample->{token_stats}->{$token};
                
            $sample->{token_stats}->{$token}++; # update the count of how many documents word has been seen in
            if(!defined $uniq_tokens_in_sample{$token}) {
                $self->{encountered_tokens}->{$token}++ ; # update the count of how many documents word has been seen in
            }
            $uniq_tokens_in_sample{$token} = 1;
            
            foreach my $label (@{$sample->{labels}}) {
                $self->{encountered_labels}->{$label} = {} if !defined $self->{encountered_labels}->{$label};
                $self->{encountered_tokens_under_labels}->{$token} = 0 if !defined $self->{encountered_tokens_under_labels}->{$token};

                $self->{encountered_labels}->{$label}->{$token}++;
                $self->{encountered_tokens_under_labels}->{$token}++ if $self->{encountered_labels}->{$label}->{$token} == 1; # update the count of how many tags word has been seen for
            }
        }
    }
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
    
    my @most_likely_classifications;
    
    my $keytokens = $self->_getKeytokens($sample, $opts);
    
    # reset the scores
    foreach my $label (keys %{$self->{encountered_labels}}) {
        $self->{encountered_labels}->{$label}->{_score} = 0;
    }
    
    foreach my $label (keys %{$self->{encountered_labels}}) {
        my $tag_score = 0;
        
        foreach my $token (@$keytokens) {
            my $documentSetSize = scalar (keys %{$self->{encountered_labels}});
            my $numOfDocsContainingToken = $self->{encountered_tokens_under_labels}->{$token} || 1;
            my $tokenFreqForTag = $self->{encountered_labels}->{$label}->{$token} || 1;
            
            $tag_score += $tokenFreqForTag * log($documentSetSize/$numOfDocsContainingToken);
        }
        
        $self->{encountered_labels}->{$label}->{_score} = $tag_score;
    }
    
    @most_likely_classifications = sort {$self->{encountered_labels}->{$b}->{_score} <=> 
        $self->{encountered_labels}->{$a}->{_score} } keys %{$self->{encountered_labels}};
    
    if($opts->{return_multiple_classifications}) {
        my $desired_amount = $opts->{return_multiple_classifications};
        return [@most_likely_classifications[0..$desired_amount-1]];
    }
    
    return $most_likely_classifications[0];
}

sub _getKeytokens
{
    my ($self, $sample, $opts) = @_;
    
    my %token_scores = ();
    my @keytokens = ();
    my $clean_tokens = $self->_clean($sample->{tokens});
    
    foreach my $token (@$clean_tokens) {
        $sample->{token_stats}->{$token} = 0 
            if !$sample->{token_stats}->{$token};
            
        $sample->{token_stats}->{$token}++; # update the count of how many documents word has been seen in
    }
    
    foreach my $token (keys %{$sample->{token_stats}}) {
        my $documentSetSize = scalar @{$self->{training_data}};
        my $numOfDocsContainingToken = $self->{encountered_tokens}->{$token} || 1;
        my $tokenFreqInSample = $sample->{token_stats}->{$token} || 1;
        
        $token_scores{$token} = $tokenFreqInSample * log($documentSetSize/$numOfDocsContainingToken);
    }
    
    @keytokens = sort {$token_scores{$b} <=> $token_scores{$a}} (keys %token_scores);
    my $numOfTokensToReturn = KEYWORDSPERQUERY > scalar @keytokens ? scalar @keytokens - 1 : KEYWORDSPERQUERY-1;
    
    return [@keytokens[0..$numOfTokensToReturn]];
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
