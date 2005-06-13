# WordNet::SenseRelate::Context::NearestWords v0.01
# (Last updated $Id: NearestWords.pm,v 1.7 2005/06/13 05:53:49 sidz1979 Exp $)

package WordNet::SenseRelate::Context::NearestWords;

use strict;
use warnings;
use Exporter;

our @ISA     = qw(Exporter);
our $VERSION = '0.01';

# Constructor for this module
sub new
{
    my $class = shift;
    my $wntools = shift;
    my $trace = shift;
    my $config = shift;
    my $self  = {};

    # Create the context selection object
    $class = ref $class || $class;
    bless($self, $class);

    $self->{wntools} = $wntools; # Check for error here.
    $self->{trace} = (($trace) ? 1 : 0);
    $self->{stop} = {};

    # Get options "window-size" and "stopwords".
    if(defined $config && ref($config) eq "HASH")
    {
        $self->{count} = $config->{windowsize} if(defined $config->{windowsize} && $config->{windowsize} =~ /[0-9]+/);
        if(defined $config->{windowstop})
        {
            open(STOP, $config->{windowstop}) || return undef;
            while(<STOP>)
            {
                s/[\r\f\n]//;
                s/\s+$//;
                s/^\s+//;
                my ($stopword) = split(/\s+/);
                $self->{stop}->{$stopword} = 1;
            }
            close(STOP);
        }
	$self->{contextpos} = $config->{contextpos} if(defined $config->{contextpos}
                                                       && $config->{contextpos} =~ /^[nvar]+$/);
    }

    return $self;
}

# Select the context words from the context
sub process
{
    my $self   = shift;
    my $intext = shift;
    my $count  = $self->{count};
    my $poses  = $self->{poses};
    my $contextpos = $self->{contextpos};
    $count = 5      if (!defined $count || $count !~ /^[0-9]+$/);
    $poses = "nvar" if (!defined $poses || $poses !~ /^[nvar]*$/);
    return undef if (!defined $self   || !ref $self);
    return undef if (!defined $intext || !defined $intext->{wordobjects});
    return undef if (ref($intext->{wordobjects}) ne "ARRAY");
    my $i    = 1;
    my $done = 1;
    return undef
      if (!defined $i || $i < 0 || $i >= scalar(@{$intext->{wordobjects}}));
    my $context = {};
    $context->{words}       = [];
    $context->{text}        = [];
    $context->{head}        = -1;
    $context->{target}      = -1;
    $context->{wordobjects} = [];
    $context->{lexelt}      = $intext->{lexelt} if (defined $intext->{lexelt});
    $context->{id}          = $intext->{id} if (defined $intext->{id});
    $context->{answer}      = $intext->{answer} if (defined $intext->{answer});
    $context->{targetpos}   = $intext->{targetpos}
      if (defined $intext->{targetpos});
    $context->{contextwords} = [];

    # Check that the text segments exist
    if (defined $intext->{text})
    {
        foreach my $textseg (@{$intext->{text}})
        {
            push(@{$context->{text}}, $textseg);
        }
    }
    $context->{head} = $intext->{head} if (defined $intext->{head});

    # Move the target to the context object
    my $targetptr;
    if (   defined $intext->{target}
        && $intext->{target} >= 0
        && $intext->{target} < scalar(@{$intext->{wordobjects}}))
    {
        $context->{target} = $intext->{target};
        if (defined $intext->{words})
        {
            foreach my $textseg (@{$intext->{words}})
            {
                push(@{$context->{words}}, $textseg);
            }
        }
        if (defined $intext->{wordobjects})
        {
            foreach my $textseg (@{$intext->{wordobjects}})
            {
                push(@{$context->{wordobjects}}, $textseg);
            }
        }
        $targetptr                   = $intext->{target};
        $context->{targetword}       = $intext->{words}->[$targetptr];
        $context->{targetwordobject} = $intext->{wordobjects}->[$targetptr];
    }
    else
    {
        return undef;
    }
    while (
           $done < $count
           && (   $targetptr - $i >= 0
               || $targetptr + $i < scalar(@{$intext->{wordobjects}}))
      )
    {
        if ($targetptr + $i < scalar(@{$intext->{wordobjects}}))
        {
            my $wordobj = $intext->{wordobjects}->[$i + $targetptr];
            $wordobj->computeSenses($self->{wntools}->{wn}, $contextpos) if(defined $contextpos);
            foreach my $pos (split(//, $poses))
            {
                if ($wordobj->{poslist} =~ $pos
                    && scalar($wordobj->getSenses()) > 0
                    && !defined $self->{stop}->{$wordobj->getWord()})
                {
                    push(@{$context->{contextwords}}, $wordobj);
                    $done++;
                    last;
                }
            }
            last if ($done >= $count);
        }
        $i++;
        if ($targetptr - $i >= 0)
        {
            my $wordobj = $intext->{wordobjects}->[$targetptr - $i];
            $wordobj->computeSenses($self->{wntools}->{wn}, $contextpos) if(defined $contextpos);
            foreach my $pos (split(//, $poses))
            {
                if ($wordobj->{poslist} =~ $pos
                    && scalar($wordobj->getSenses()) > 0
                    && !defined $self->{stop}->{$wordobj->getWord()})
                {
                    push(@{$context->{contextwords}}, $wordobj);
                    $done++;
                    last;
                }
            }
            last if ($done >= $count);
        }
        $i++;
    }
    
    return $context;
}

1;

__END__

=head1 NAME

WordNet::SenseRelate::Context::NearestWords - Perl module for selecting the N nearest words as 
the context of the target word.

=head1 SYNOPSIS

  use WordNet::SenseRelate::Context::NearestWords;

  $selector = WordNet::SenseRelate::NearestWords->new($wntools);

  $context = $selector->process($instance);

=head1 DESCRIPTION

This module selects the N words nearest the target word, as the context of the target word.
By default the value of N is 5, however this can be changed using the options hash. The
selected context object includes the target word.

=head2 EXPORT

None by default.

=head1 SEE ALSO

perl(1)

WordNet::SenseRelate::TargetWord(3)

=head1 AUTHOR

Siddharth Patwardhan, sidd at cs.utah.edu

Satanjeev Banerjee, satanjeev at cs cmu.edu

Ted Pedersen, tpederse at d.umn.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Siddharth Patwardhan, Satanjeev Banerjee and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut