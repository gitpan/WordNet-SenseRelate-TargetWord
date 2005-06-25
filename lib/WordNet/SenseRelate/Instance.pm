# WordNet::SenseRelate::Instance v0.02
# (Last updated $Id: Instance.pm,v 1.4 2005/06/24 13:55:37 sidz1979 Exp $)

package WordNet::SenseRelate::Instance;

use strict;
use vars qw($VERSION @ISA);

@ISA     = qw(Exporter);
$VERSION = '0.02';

# Constructor for this module
sub new
{
    my $class = shift;
    my $self  = {};

    # Create the Instance object
    $class = ref $class || $class;
    bless($self, $class);

    # Set the Instance
    $self->{word} = "";
    my $word = shift;
    $self->{word} = $word if (defined $word);

    return $self;
}

# Return the Instance
sub getInstance
{
    my $self = shift;
    return undef if (!defined $self || !ref $self);
    return $self->{word};
}

1;

__END__

=head1 NAME

WordNet::SenseRelate::Instance - Perl module that represents a context, including a target
word and surrounding context words.

=head1 SYNOPSIS

  use WordNet::SenseRelate::Instance;

=head1 DESCRIPTION

WordNet::SenseRelate::Instance represents a piece of text, including a target word that
requires to be disambiguated. Essentially, an instance is a set of Word objects, with
one Word object marked as the target word.

=head2 EXPORT

None by default.

=head1 SEE ALSO

perl(1)

WordNet::SenseRelate::TargetWord(3)

WordNet::SenseRelate::Word(3)

=head1 AUTHOR

Siddharth Patwardhan, sidd at cs.utah.edu>

Satanjeev Banerjee, banerjee+ at cs.cmu.edu

Ted Pedersen, tpederse at d.umn.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Siddharth Patwardhan, Satanjeev Banerjee and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
