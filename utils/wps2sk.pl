#! /usr/local/bin/perl -w
# (Updated: $Id: wps2sk.pl,v 1.3 2005/06/08 13:49:24 sidz1979 Exp $)
#
# wps2sk.pl version 0.1
#
# Program to convert SENSEVAL answer files with answers in the
# word#pos#sense format to mnemonics using the word#pos#sense -
# mnemonic mapping from WordNet.
#
# Copyright (c) 2005
#
# Satanjeev Banerjee, Carnegie Mellon University
# satanjeev@cs.cmu.edu
#
# Ted Pedersen, University of Minnesota, Duluth
# tpederse@d.umn.edu
#
# Siddharth Patwardhan, University of Utah
# sidd@cs.utah.edu
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#-----------------------------------------------------------------------------

# we have to use commandline options, so use the necessary package!
use Getopt::Long;

# now get the options!
&GetOptions("help", "wnpath=s",  "version");

# If the version information has been requested
if(defined $opt_version)
{
    $opt_version = 1;
    &printVersion();
    exit;
}

# if help has been requested, print out help!
if(defined $opt_help)
{
    $opt_help = 1;
    &showHelp();
    exit;
}

# Check if path to WordNet Data files has been provided ... If so ... save it.
if(defined $opt_wnpath)
{
    $wnPCPath = $opt_wnpath;
    $wnUnixPath = $opt_wnpath;
}
else
{
    $wnPCPath = (defined $ENV{"WNHOME"}) ? $ENV{"WNHOME"} : "C:\\Program Files\\WordNet\\1.7";
    $wnUnixPath = (defined $ENV{"WNHOME"}) ? $ENV{"WNHOME"} : "/usr/local/wordnet1.7";
    $wnPCPath = (defined $ENV{"WNSEARCHDIR"}) ? $ENV{"WNSEARCHDIR"} : $wnPCPath."\\dict";
    $wnUnixPath = (defined $ENV{"WNSEARCHDIR"}) ? $ENV{"WNSEARCHDIR"} : $wnUnixPath."/dict";    
}

# Open sense index file
open(SENSE, $wnUnixPath."/index.sense") || open(SENSE, $wnPCPath."\\sense.idx") || die "Unable to open sense index file.\n";


# Load up the sense file in a hash. Keys of the hash will be
# lemma::offset - This is unique to each sense key. Values of the hash
# will be the actual sense keys.

print STDERR "Loading sense index file... ";

while(<SENSE>)
{
    s/[\r\f\n]//g;

    if($_ !~ /((\S+)%\S+)\s+(\d+)/)
    { 
	print STDERR "Error in sense index file. ";
	print STDERR "Read \"$_\". Expecting \"<sense-key> <offset> ...\"\n";
	exit;
    }

    my $key = $2 . "::" . $3;
    my $value = $1;

    if(defined $senseHash{$key}) { print STDERR "$key already defined!\n"; }
    $senseHash{$key} = $value;
}

print STDERR "done!\n";

# done with the index.sense file 
close(SENSE);

# now do everything for each part of speech!
my $pos;
my %mapHash = ();
foreach $pos ("noun", "verb", "adj", "adv")
{
    print STDERR "Processing index.$pos file... ";
    
    # open index file
    open(INDEX, $wnUnixPath."/index.$pos") || open(INDEX, $wnPCPath."\\$pos.idx") || die "Unable to open index file.\n";
    
    while(<INDEX>)
    {
	next if(/^ /);
	s/[\r\f\n]//g;
	
	# get the lemma and the number of senses
	my ($lemma, $p, $noOfSenses, @rest) = split /\s+/;
	
	# for each sense of this lemma, create the key (for the above
	# hash) and find the 
	for($i = $#rest - $noOfSenses + 1; $i <= $#rest; $i++)
	{
	    my $key = $lemma . "::" . $rest[$i];
	    if(!defined $senseHash{$key}) { print STDERR "$key not defined!!\n"; exit; }
	    my $tmpNum = ($i - ($#rest - $noOfSenses + 1) + 1);
	    $mapHash{"$lemma\#$p\#$tmpNum"} = $senseHash{$key};
	}
    }
    close(INDEX);
    print STDERR "done!\n";
}

while (<>)
{
    s/[\r\f\n]//g;

    # get the index part and the answer part
    my @answers = ();
    if(/^(\S+\s+\S+)\s+(.*)\s*/)
    {
        my $part1 = $1;
        @answers = split (/\s+/, $2);
        $part1 =~ s/\.[nvar]//;
        print "$part1 ";
    }

    # convert answers
    my $ans;
    foreach $ans (@answers)
    {
	if (defined $mapHash{$ans}) { print "$mapHash{$ans} "; }
	else { print STDERR "Couldnt find mapping for $ans\n"; }
    }
    print "\n";
}

# function to output help messages for this program
sub showHelp
{
    print "Creates a word#pos#sense to sensekey mapping of a Senseval-2 answer file\n";
    print "(output by disamb.pl).\n";
    print "Usage: wps2sk.pl [ [ --wnpath WNPATH] [FILE...] | --help | --version ]\n";
    print "--wnpath         WNPATH specifies the path of the WordNet data files.\n";
    print "                 Ordinarily, this path is determined from the \$WNHOME\n";
    print "                 environment variable. But this option overides this\n";
    print "                 behavior.\n";
    print "--help           Displays this help screen.\n";
    print "--version        Displays version information.\n\n";    
}

# function to output "ask for help" message when the user's goofed up!
sub askHelp
{
    print "Type wps2sk.pl --help for help.\n";
}

# Subroutine to print the version information
sub printVersion
{
    print "wps2sk.pl version 0.1\n";
    print "Copyright (c) 2005 Satanjeev Banerjee, Ted Pedersen and Siddharth Patwardhan.\n";
}

__END__

=head1 NAME

wps2sk.pl - Tool that converts the output from disamb.pl to a Senseval-2 format (such that it can
be easily evaluated by the Senseval-2 evaluation software).

=head1 SYNOPSIS

wps2sk.pl [ [ --wnpath WNPATH] [FILE...] | --help | --version ]

=head1 DESCRIPTION

Creates a word#pos#sense to sensekey mapping of a Senseval-2 answer file (output by disamb.pl). It takes
the output of disamb.pl and converts it to a format that is understood by the Senseval-2 evaluation software.

=head1 OPTIONS

wps2sk.pl [ [ --wnpath WNPATH] [FILE...] | --help | --version ]

B<--wnpath>=I<WNPATH>         
    WNPATH specifies the path of the WordNet data files. Ordinarily, this path is determined from the $WNHOME
    environment variable. But this option overides this behavior.

B<--help>
    Displays this help screen.

B<--version>
    Displays version information.

=head1 AUTHORS

 Siddharth Patwardhan <sidd at cs.utah.edu>

 Ted Pedersen <tpederse at d.umn.edu>

 Satanjeev Banerjee <satanjeev at cmu.edu>

=head1 BUGS

=head1 SEE ALSO

perl(1)

WordNet::SenseRelate::TargetWord(3)

WordNet::Similarity(3)

http://www.cogsci.princeton.edu/~wn/

http://senserelate.sourceforge.net

http://groups.yahoo.com/group/senserelate/

=head1 COPYRIGHT

Copyright (c) 2005 Siddharth Patwardhan, Ted Pedersen, Satanjeev
Banerjee

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut