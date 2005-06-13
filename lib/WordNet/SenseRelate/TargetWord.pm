# WordNet::SenseRelate::TargetWord v0.06
# (Last Updated $Id: TargetWord.pm,v 1.8 2005/06/08 13:49:24 sidz1979 Exp $)
package WordNet::SenseRelate::TargetWord;

use 5.006;
use strict;
use warnings;

require Exporter;

our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ('all' => [qw()]);
our @EXPORT_OK   = (@{$EXPORT_TAGS{'all'}});
our @EXPORT      = qw();
our $VERSION     = '0.06';

# CONSTRUCTOR: Creates new SenseRelate::TargetWord object.
# Returns the created object.
sub new
{
    my $class   = shift;
    my $self    = {};
    my $modules = {};

    # Create the TargetWord object
    $class = ref $class || $class;
    bless($self, $class);

    # Set the default options first
    $modules->{preprocess} = [];
    push(
         @{$modules->{preprocess}},
         "WordNet::SenseRelate::Preprocess::Compounds"
    );
    $modules->{preprocessconfig} = [];
    $modules->{context}       = "WordNet::SenseRelate::Context::NearestWords";
    $modules->{contextconfig} = undef;
    $modules->{postprocess}   = [];
    $modules->{postprocessconfig} = [];
    $modules->{algorithm}     = "WordNet::SenseRelate::Algorithm::Random";
    $modules->{algorithmconfig} = undef;
    $modules->{measure}       = "WordNet::Similarity::lesk";
    $modules->{measureconfig} = undef;
    $modules->{wntools}       = undef;

    # Get the options
    my $options = shift;
    my $trace = shift;
    $trace = 0 if(!defined $trace);
    if (defined $options && ref($options) eq "HASH")
    {
        # Get the Preprocessor modules
        if (defined $options->{preprocess}
            && ref($options->{preprocess}) eq "ARRAY")
        {
            $modules->{preprocess} = [];
            push(@{$modules->{preprocess}}, @{$options->{preprocess}});
        }

        # Get configuration options for preprocessor modules
        if (defined $options->{preprocessconfig}
            && ref($options->{preprocessconfig}) eq "ARRAY")
        {
            $modules->{preprocessconfig} = [];
            push(@{$modules->{preprocessconfig}}, @{$options->{preprocessconfig}});
        }

        # Get context selection module
        $modules->{context} = $options->{context}
          if (defined $options->{context});

        # Get configuration options for context selection module
        $modules->{contextconfig} = $options->{contextconfig}
          if(defined $options->{contextconfig} && ref($options->{contextconfig}) eq "HASH");

        # Get postprocess modules
        if (defined $options->{postprocess}
            && ref($options->{postprocess}) eq "ARRAY")
        {
            $modules->{postprocess} = [];
            push(@{$modules->{postprocess}}, @{$options->{postprocess}});
        }

        # Get configuration options for postprocess modules
        if (defined $options->{postprocessconfig}
            && ref($options->{postprocessconfig}) eq "ARRAY")
        {
            $modules->{postprocessconfig} = [];
            push(@{$modules->{postprocessconfig}}, @{$options->{postprocessconfig}});
        }

        # Get algorithm module
        $modules->{algorithm} = $options->{algorithm}
          if (defined $options->{algorithm});

        # Get configuration options for algorithm module
        $modules->{algorithmconfig} = $options->{algorithmconfig}
          if (defined $options->{algorithmconfig});

        # Get semantic relatedness module
        $modules->{measure} = $options->{measure}
          if (defined $options->{measure});

        # Get configuration options for semantic relatedness module
        $modules->{measureconfig} = $options->{measureconfig}
          if (defined $options->{measureconfig});

        # Get the WordNet::SenseRelate::Tools
        $modules->{wntools} = $options->{wntools}
          if (defined $options->{wntools} && ref($options->{wntools}) eq "WordNet::SenseRelate::Tools");
    }

    # Load WordNet::SenseRelate::Tools
    my $wntools = $modules->{wntools};
    if (   !defined $wntools
        || !ref $wntools
        || ref($wntools) ne "WordNet::SenseRelate::Tools")
    {
        $wntools = WordNet::SenseRelate::Tools->new($wntools);
        return (
            undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load WordNet::SenseRelate::Tools\n"
          )
          if (!defined $wntools);
    }
    $self->{wntools} = $wntools;

    # Load all the modules
    my $module;
    my $modulePath;

    # Load Preprocessor modules
    $self->{preprocess} = [];
    foreach my $i (0 .. scalar(@{$modules->{preprocess}}) - 1)
    {
        my $preproc = $modules->{preprocess}->[$i];
        $modulePath = $modules->{preprocess}->[$i];
        $modulePath =~ s/::/\//g;
        $modulePath .= ".pm";
        require $modulePath;
        $module = $preproc->new($wntools, $trace, $modules->{preprocessconfig}->[$i]);
        return (
            undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load preprocess module $preproc\n"
          )
          if (!defined($module));
        push(@{$self->{preprocess}}, $module);
    }

    # Load Context Selection module
    $modulePath = $modules->{context};
    $modulePath =~ s/::/\//g;
    $modulePath .= ".pm";
    require $modulePath;
    $module = $modules->{context}->new($wntools, $trace, $modules->{contextconfig});
    return (undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load context selection module "
          . ($modules->{context}) . "\n")
      if (!defined($module));
    $self->{context} = $module;

    # Load Postprocessor modules
    $self->{postprocess} = [];
    foreach my $i (0 .. scalar(@{$modules->{postprocess}}) - 1)
    {
        my $postproc = $modules->{postprocess}->[$i];
        $modulePath = $postproc;
        $modulePath =~ s/::/\//g;
        $modulePath .= ".pm";
        require $modulePath;
        $module = $postproc->new($wntools, $trace, $modules->{postprocessconfig}->[$i]);
        return (
            undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load postprocess module $postproc\n"
          )
          if (!defined($module));
        push(@{$self->{postprocess}}, $module);
    }

    # Load Similarity module
    $modulePath = $modules->{measure};
    $modulePath =~ s/::/\//g;
    $modulePath .= ".pm";
    require $modulePath;
    $module =
      $modules->{measure}->new($wntools->{wn}, $modules->{measureconfig});
    return (undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load similarity measure module "
          . ($modules->{measure}) . "\n")
      if (!defined($module));
    $module->{'trace'} = 2 if($trace);
    $self->{measure} = $module;
    my $measurepos = "";
    foreach my $mypos ('n', 'v', 'a', 'r')
    {
        $measurepos .= $mypos if(defined $module->{$mypos});
    }
    $measurepos = "nvar" if($measurepos eq "");
    $self->{contextpos} = $measurepos;

    # Load Disambiguation Algorithm module
    $modulePath = $modules->{algorithm};
    $modulePath =~ s/::/\//g;
    $modulePath .= ".pm";
    require $modulePath;
    $module = $modules->{algorithm}->new($wntools, $self->{measure}, $trace, $modules->{algorithmconfig});
    return (undef,
"WordNet::SenseRelate::TargetWord->new() -- Unable to load disambiguation module "
          . ($modules->{algorithm}) . "\n")
      if (!defined($module));
    $self->{algorithm} = $module;
    
    $self->{trace} = $trace;

    return ($self, undef);
}

# Takes an instance object and disambiguates the target word
# Returns the selected sense of the target word
sub disambiguate
{
    my $self     = shift;
    my $instance = shift;
    my $sense;
    my $wntools = $self->{wntools};

    return undef
      if (   !defined($self)
          || !ref($self)
          || ref($self) ne "WordNet::SenseRelate::TargetWord");
    return undef if (!defined($instance) || !ref($instance));

    # Preprocess the instance
    foreach my $preproc (@{$self->{preprocess}})
    {
        $instance = $preproc->preprocess($instance);
    }

    # Required processing of words:
    # (a) Get the base forms of all words
    # (b) Get the possible parts of speech
    # (c) Get the possible senses
    foreach my $i (0 .. scalar(@{$instance->{wordobjects}}) - 1)
    {
        $instance->{wordobjects}->[$i]->computeSenses($wntools->{wn}, $self->{contextpos});
    }

    # Select context
    $instance = $self->{context}->process($instance);

    # Postprocess the instance
    foreach my $postproc (@{$self->{postprocess}})
    {
        $instance = $postproc->postprocess($instance);
    }

    # Get target sense
    $sense = $self->{algorithm}->disambiguate($instance);
    
    return $sense;
}

1;


__END__


=head1 NAME

WordNet::SenseRelate::TargetWord - Perl module for performing word sense disambiguation.

=head1 SYNOPSIS

  use WordNet::SenseRelate::TargetWord;
  
  $tool = WordNet::SenseRelate::TargetWord->new();

  $sense = $tool->disambiguate($instance);

=head1 DESCRIPTION

WordNet::SenseRelate::TargetWord combines the different parts of the word sense disambiguation
process. It allows the user to select the disambiguation algorithm, the context selection algorithm, 
and other data processing tasks. This module applies these to the context and returns the selected
sense.

=head2 EXPORT

None by default.

=head1 SEE ALSO

perl(1)

WordNet::Similarity(3)

http://www.cogsci.princeton.edu/~wn/

http://senserelate.sourceforge.net

http://groups.yahoo.com/group/senserelate/

=head1 AUTHOR

Siddharth Patwardhan, sidd at cs.utah.edu

Satanjeev Banerjee, satanjeev at cs.cmu.edu

Ted Pedersen, tpederse at d.umn.edu

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2005 by Siddharth Patwardhan, Satanjeev Banerjee and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
