# WordNet::SenseRelate::Algorithm::Global v0.01
# (Last updated $Id: Global.pm,v 1.5 2005/06/08 13:49:24 sidz1979 Exp $)

package WordNet::SenseRelate::Algorithm::Global;

use strict;
use warnings;
use Exporter;

our @ISA     = qw(Exporter);
our $VERSION = '0.01';

# Constructor for this module
sub new
{
    my $class   = shift;
    my $wntools = shift;
    my $self    = {};
    my $measure = shift;
    my $trace   = shift;
    my $config  = shift;

    # Create the preprocessor object
    $class = ref $class || $class;
    bless($self, $class);

    # Load similarity measure
    return undef
      if (   !defined $measure
          || !ref($measure)
          || !($measure->can('getRelatedness')));
    $self->{measure} = $measure;

    # Read in the wordnet data, if required
    if (   !defined $wntools
        || !ref($wntools)
        || ref($wntools) ne "WordNet::SenseRelate::Tools")
    {
        my $wnpath = undef;
        $wnpath = $wntools
          if (defined $wntools && !ref($wntools) && $wntools ne "");
        $wntools = WordNet::SenseRelate::Tools->new($wnpath);
        return undef if (!defined $wntools);
    }
    $self->{wntools} = $wntools;

    return $self;
}

# Select the intended sense of the target word
sub disambiguate
{
    my $self    = shift;
    my $context = shift;

    return undef if (!defined $self || !ref $self || !defined $context);
    return undef
      if (   !defined $context->{targetwordobject}
          || !defined $context->{contextwords});
    return undef
      if (   ref($context->{contextwords}) ne "ARRAY"
          || ref($context->{targetwordobject}) ne "WordNet::SenseRelate::Word");

    my $measure      = $self->{measure};
    my $targetWord   = $context->{targetwordobject};
    my @targetSenses = $targetWord->getSenses();
    return undef if (scalar(@targetSenses) <= 0);

    my $nameHash = {};
    foreach my $targetSense (@targetSenses)
    {
        $self->_getCombinations($targetSense, $context->{contextwords},
                                0, $nameHash);
    }

    foreach my $nameCombo (keys(%{$nameHash}))
    {
        my @sensesInCombo = split(/::/, $nameCombo);
        foreach my $i (0 .. ($#sensesInCombo - 1))
        {
            foreach my $j ($i + 1 .. $#sensesInCombo)
            {
                $nameHash->{$nameCombo} +=
                  $measure->getRelatedness($sensesInCombo[$i],
                                           $sensesInCombo[$j]);
            }
        }
    }

    my ($first) = sort {$nameHash->{$b} <=> $nameHash->{$a}} keys %{$nameHash};
    my ($selectedSense) = split(/::/, $first);

    return $selectedSense;
}

sub _getCombinations
{
    my $self         = shift;
    my $currString   = shift;
    my $contextWords = shift;
    my $level        = shift;
    my $nameHash     = shift;

    if ($level >= scalar(@{$contextWords}))
    {
        $nameHash->{$currString} = 0;
        return;
    }
    my $word = $contextWords->[$level];

    foreach my $sense ($word->getSenses())
    {
        $self->_getCombinations($currString . "::" . $sense,
                                $contextWords, $level + 1, $nameHash);
    }
}

1;


__END__


=head1 NAME

WordNet::SenseRelate::Algorithm::Global - Perl module that finds the sense of a target word
that is most related to its context.

=head1 SYNOPSIS

  use WordNet::SenseRelate::Algorithm::Global;

  $algo = WordNet::SenseRelate::Algorithm::Global->new($wntools, $measure);

  $sense = $algo->disambiguate($instance);

=head1 DESCRIPTION

This modules uses a measure of relatedness (WordNet::Similarity module) to find the relatedness of
each sense of the target word with the senses of the words in the context. It then return the
most related sense of the target word.

=head2 EXPORT

None by default.

=head1 SEE ALSO

perl(1)

WordNet::SenseRelate::TargetWord(3)

=head1 AUTHOR

Siddharth Patwardhan, sidd at cs.utah.edu

Satanjeev Banerjee, satanjeev at cs.cmu.edu

Ted Pedersen, tpederse at d.umn.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Siddharth Patwardhan, Satanjeev Banerjee and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut