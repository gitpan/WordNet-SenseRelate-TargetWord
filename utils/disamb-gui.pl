#! /usr/local/bin/perl -w
# (Updated: $Id: disamb-gui.pl,v 1.5 2005/06/25 09:53:16 sidz1979 Exp $)
#
# disamb-gui.pl version 0.07
#
# Program that reads in a Senseval-2 formatted lexical sample file, and
# disambiguates the instances using WordNet::SenseRelate::TargetWord.
#
# Copyright (c) 2005
#
# Satanjeev Banerjee, Carnegie Mellon University
# banerjee+@cs.cmu.edu
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

# Uses:
use strict;
use WordNet::SenseRelate::Reader::Senseval2;
use WordNet::SenseRelate::TargetWord;
use WordNet::SenseRelate::Tools;
use Getopt::Long;
use Gtk;

# Now get the options!
our ($opt_config, $opt_wnpath, $opt_help, $opt_version);
&GetOptions("config=s", "wnpath=s", "help", "version");

# My global variables
my $VERSION = '0.07';
my $options = {};
my $lastDir = undef;
my $instanceData = undef;
my $wntools;
my $targetWord;
my $error;
my $esColor = {};
my @warnings = ();
my %posMap = ('n' => 'NOUN',
              'v' => 'VERB',
              'a' => 'ADJECTIVE',
              'r' => 'ADVERB');
my %moduleNames = ('PREPROCESS' => ['WordNet::SenseRelate::Preprocess::Compounds'],
                   'POSTPROCESS' => [],
                   'CONTEXT' => ['WordNet::SenseRelate::Context::NearestWords'],
                   'ALGORITHM' => ['WordNet::SenseRelate::Algorithm::Local', 
                                   'WordNet::SenseRelate::Algorithm::Global',
                                   'WordNet::SenseRelate::Algorithm::SenseOne',
                                   'WordNet::SenseRelate::Algorithm::Random']);
my %moduleOptions = ('WordNet::SenseRelate::Preprocess::Compounds' => {},
                     'WordNet::SenseRelate::Context::NearestWords' => {'contextpos' => 's!!0!!nvar',
                                                                       'windowsize' => 'i!!0!!5',
                                                                       'windowstop' => 'f!!0!!'},
                     'WordNet::SenseRelate::Algorithm::Local' => {'measure' => 'm!!0!!WordNet::Similarity::vector',
                                                                  'measureconfig' => 'f!!0!!'},
                     'WordNet::SenseRelate::Algorithm::Global' => {'measure' => 'm!!0!!WordNet::Similarity::vector',
                                                                   'measureconfig' => 'f!!0!!'},
                     'WordNet::SenseRelate::Algorithm::SenseOne' => {}, 
                     'WordNet::SenseRelate::Algorithm::Random' => {});

# If help is requested
if (defined $opt_help)
{
    &printHelp();
    exit;
}

# If version information is requested
if (defined $opt_version)
{
    &printVersion();
    exit;
}

# Load configuration options, if config file specified.
# (Pop warning message box, if error reading config file)
# Else set up default configuration
if(defined $opt_config)
{
    # Make all the options undefined first
    $options                      = {};
    $options->{preprocess}        = [];
    $options->{preprocessconfig}  = [];
    $options->{postprocess}       = [];
    $options->{postprocessconfig} = [];
    $options->{context}           = undef;
    $options->{contextconfig}     = undef;
    $options->{algorithm}         = undef;
    $options->{algorithmconfig}   = undef;
    $options->{wntools}           = undef;

    # Read the configuration file
    my $optStruct = &readConfigFile($opt_config);
    if (!defined $optStruct)
    {
        &askHelp("disamb.pl: Configuration file format error.\n");
        $options = {};
    }
    else
    {
        # Now get the options from the options structure
        # First, the preprocess modules and options
        if (defined $optStruct->{'PREPROCESS'})
        {
            foreach my $element (@{$optStruct->{'PREPROCESS'}})
            {
                push(@{$options->{preprocess}}, $element->{'name'});
                delete $element->{'name'};
                push(@{$options->{preprocessconfig}}, $element);
            }
        }
        
        # Next, the postprocess modules and options
        if (defined $optStruct->{'POSTPROCESS'})
        {
            foreach my $element (@{$optStruct->{'POSTPROCESS'}})
            {
                push(@{$options->{postprocess}}, $element->{'name'});
                delete $element->{'name'};
                push(@{$options->{postprocessconfig}}, $element);
            }
        }

        # Next, get the context selection module and options
        if (defined $optStruct->{'CONTEXT'})
        {
            
            # There should be only one context selection module specified
            &askHelp("disamb.pl: Multiple context selection modules specified in configuration file. Using first.")
                if (scalar(@{$optStruct->{'CONTEXT'}}) > 1);

            # Get the context selection module name, and options
            # If none are specified, the default will be used
            my $element = shift(@{$optStruct->{'CONTEXT'}});
            if (defined $element && defined $element->{'name'})
            {
                $options->{context} = $element->{'name'};
                delete $element->{'name'};
                $options->{contextconfig} = $element;
            }
        }

        # Next, get the algorithm module and options
        if (defined $optStruct->{'ALGORITHM'})
        {

            # Only one algorithm module must be specified
            &askHelp("disamb.pl: Multiple algorithm modules specified in configuration file. Using first.")
                if (scalar(@{$optStruct->{'ALGORITHM'}}) > 1);

            # Get the algorithm module name, and options
            # If none are specified, then the default will be used
            my $element = shift(@{$optStruct->{'ALGORITHM'}});
            if (defined $element && defined $element->{'name'})
            {
                $options->{algorithm} = $element->{'name'};
                delete $element->{'name'};
                $options->{algorithmconfig} = $element;
            }
        }
    }
}

# Load WordNet::SenseRelate::Tools...
# Exit with warning message, if unable to load...
print STDERR "Loading WordNet::SenseRelate::Tools... ";
$wntools = WordNet::SenseRelate::Tools->new($opt_wnpath);
if(!defined $wntools)
{
    print STDERR "disamb-gui.pl: Unable to load WordNet::SenseRelate::Tools.\n";
    print STDERR "Type \'disamb-gui.pl --help\' for help.\n";
    exit;
}
print STDERR "done.\n";
$options->{'wntools'} = $wntools;

# Load WordNet::SenseRelate::TargetWord...
# Exit with warning message, if unable to load...
print STDERR "Loading WordNet::SenseRelate::TargetWord... ";
($targetWord, $error) = WordNet::SenseRelate::TargetWord->new($options, 1);
if (!defined $targetWord)
{
    print STDERR "$error\n";
    exit;
}
print STDERR "done.\n";

# Call "readXMLFile", if an argument was passed
if(scalar(@ARGV) > 0)
{
    print STDERR "Reading XML data... ";
    $instanceData = WordNet::SenseRelate::Reader::Senseval2->new($ARGV[0]);
    &askHelp("Error reading XML file.") if(!defined $instanceData);
    print STDERR "done.\n";
}

# Initialize Gtk.
print STDERR "Starting interface... \n";
set_locale Gtk;
init Gtk;

# Initialize colors
$esColor->{'red'} = 0xFFFF;
$esColor->{'green'} = 0xD000;
$esColor->{'blue'} = 0xD000;
my $cmap = Gtk::Gdk::Colormap->get_system();
&askHelp("Couldn't allocate green color.") unless(defined($cmap->color_alloc($esColor)));

# Build the graphical user interface
# Create the main window...
my $window = Gtk::Window->new('toplevel');
$window->set_usize(800, 515);
$window->set_policy(0, 0, 1);
#$window->set_resizable(0);
$window->signal_connect('destroy', sub{ Gtk->exit(0); });
$window->set_title("WordNet::SenseRelate::TargetWord");
$window->set_position('center');
$window->border_width(0);

# Create a menubar
my @menu_items = ( { path        => '/_File',
		     type        => '<Branch>' },
		   { path        => '/File/_Open',
		     accelerator => '<control>O',
		     callback    => \&readFileDialog },
                   { path        => '/File/_Setup',
                     accelerator => '<control>S',
                     callback    => \&setupDialog },
		   { path        => '/File/sep1',
		     type        => '<Separator>'},
		   { path        => '/File/E_xit',
		     callback    => sub { Gtk->exit(0); } },
		   { path        => '/_Help',
		     type        => '<Branch>' },
		   { path        => '/_Help/About',
                     callback    => \&showAbout } );
my $accel_group = new Gtk::AccelGroup();
my $item_factory = new Gtk::ItemFactory('Gtk::MenuBar', '<main>', $accel_group);
$item_factory->create_items(@menu_items);
$window->add_accel_group($accel_group);
my $menubar = $item_factory->get_widget('<main>');
$menubar->show();

# Create a text input box
my $textBox = Gtk::Text->new();
$textBox->set_usize(450, 200);
$textBox->set_editable(0);
$textBox->set_word_wrap(1);
$textBox->set_line_wrap(1);
$textBox->show();

# Create the scrollbar
my $vscrollbar = Gtk::VScrollbar->new($textBox->vadj);
$vscrollbar->show();

# Create a HBox
my $textHBox = Gtk::HBox->new(0, 0);
$textHBox->pack_end($vscrollbar, 0, 0, 0);
$textHBox->pack_end($textBox, 0, 0, 0);
$textHBox->show();

# Create instance label
my $inLabel = Gtk::Label->new("Instance ID: \nLexical Element: \nAnswer: \nTarget part-of-speech:");
$inLabel->set_justify('left');
$inLabel->show();
my $inFrame = Gtk::Frame->new("");
$inFrame->add($inLabel);
$inFrame->show();

# Create VBox for text and labels
my $instanceVBox = Gtk::VBox->new(0, 5);
$instanceVBox->pack_end($inFrame, 0, 0, 0);
$instanceVBox->pack_start($textHBox, 1, 1, 0);
$instanceVBox->show();

# Create clist
my $clist = Gtk::CList->new_with_titles("Id", "Lexelt", "Target POS", "   Answer");
$clist->set_selection_mode('browse');
$clist->set_column_justification(0, 'center');
$clist->set_column_justification(1, 'center');
$clist->set_column_justification(2, 'center');
$clist->set_column_justification(3, 'left');
$clist->set_column_width(0, 70);
$clist->set_column_width(1, 70);
$clist->set_column_width(2, 70);
$clist->set_column_width(3, 110);
$clist->column_titles_active();
$clist->show();

# Create a Scrolled Window for CList
my $scrolled_window = Gtk::ScrolledWindow->new();
$scrolled_window->set_policy('automatic', 'always');
$scrolled_window->add($clist);
$scrolled_window->show();

# Create HBox for clist-window and text-vbox
my $readerHBox = Gtk::HBox->new(0, 0);
$readerHBox->pack_end($instanceVBox, 0, 0, 0);
$readerHBox->pack_start($scrolled_window, 1, 1, 0);
$readerHBox->show();

# Create output Label
my $outLabel = Gtk::Label->new("Selected Sense: ");
$outLabel->set_justify('left');
$outLabel->show();

# Create output textbox
my $outText = Gtk::Text->new();
$outText->set_usize(600, 50);
$outText->set_editable(0);
$outText->set_word_wrap(1);
$outText->set_line_wrap(1);
$outText->show();

# Create VBox for output
my $outVBox = Gtk::VBox->new(0, 0);
$outVBox->pack_start($outLabel, 0, 0, 0);
$outVBox->pack_end($outText, 1, 1, 0);
$outVBox->show();

# Create disambiguate button
my $disambBox = Gtk::Button->new("Disambiguate");
$disambBox->show();

# Create table for button
my $disambTable = Gtk::Table->new(3, 1, 1);
$disambTable->attach_defaults($disambBox, 0, 1, 1, 2);
$disambTable->show();

# Create HBox for button and output
my $pHBox = Gtk::HBox->new(0, 0);
$pHBox->pack_start($disambTable, 0, 0, 0);
$pHBox->pack_end($outVBox, 1, 1, 0);
$pHBox->show();

# Create frame
my $pFrame = Gtk::Frame->new("Process");
$pFrame->add($pHBox);
$pFrame->show();

# Create a VBox
my $vbox = Gtk::VBox->new(0, 5);
$vbox->pack_start($menubar, 0, 0, 0);
$vbox->pack_start($readerHBox, 1, 1, 0);
$vbox->pack_start($pFrame, 0, 0, 0);
$vbox->show();

# Set up all the signals
$clist->signal_connect('select_row', \&displayInstanceData);
$disambBox->signal_connect('clicked', \&disambiguateInstance);

# Show the main window
$window->add($vbox);
$window->show();

# Put the data onto the form
&refreshGUI($instanceData);

# Display warnings from startup, if any
&displayStartupWarnings(@warnings) if(scalar(@warnings));

# Gtk event loop
main Gtk;

# Should never get here
exit;

# Create read Senseval file dialog
sub readFileDialog
{
    my $fDialog = Gtk::FileSelection->new("Select Senseval2 Lexical Sample File");
    $fDialog->set_policy(0, 0, 1);
    # $fDialog->set_resizable(0);
    $fDialog->set_position('center');
    $fDialog->border_width(0);
    $fDialog->set_modal(1);
    $fDialog->set_filename($lastDir) if(defined $lastDir);

    # Connect Signals
    $fDialog->ok_button->signal_connect("clicked", \&fileSelect, $fDialog);
    $fDialog->cancel_button->signal_connect("clicked", sub{ $fDialog->destroy(); });

    # Display it
    $fDialog->show();
}

# This function is a callback for the file
# selection dialog. This is where the filename
# selected by the user is determined.
sub fileSelect
{
    # Get the parameters
    my ($widget, $dialog) = @_;
    my $file;

    # The dialog pointer must be given
    return if(!defined $dialog);

    # Get the filename
    $file = $dialog->get_filename();
    $lastDir = $file if(defined $file);
    $lastDir =~ s|\/[^\/]*$||;
    $lastDir .= "/";
    $dialog->destroy();

    # Read the file
    $instanceData = &readXMLFile($file);

    # Refresh the GUI with the new data && remove "Reading file... " window
    &refreshGUI($instanceData);
}

# This method loads a Senseval2 formatted XML file
sub readXMLFile
{
    my $fname = shift;
    
    # Show message box "Unable to read XML file" if not defined $fname && return
    if(!defined $fname)
    {
        &showMessageBox("Error", "Unable to read XML file.");
        return;
    }

    # Show "Reading file... " window
    my $messybox = Gtk::Window->new('dialog');
    $messybox->set_usize(400, 100);
    $messybox->set_policy(0, 0, 1);
    # $messybox->set_resizable(0);
    $messybox->set_title("Information: Reading XML File... Please Wait.");
    $messybox->set_position('center');
    $messybox->border_width(0);
    $messybox->set_modal(1);

    #my $mesLab = Gtk::Label->new("Reading XML file. Please Wait.");
    #$mesLab->set_justify('left');
    #$mesLab->show();

    my $mesLab = Gtk::Text->new();
    $mesLab->set_usize(200, 50);
    $mesLab->set_editable(0);
    $mesLab->set_word_wrap(1);
    $mesLab->set_line_wrap(1);
    $mesLab->freeze();
    $mesLab->insert(undef, undef, undef, "Reading XML file. Please Wait.");
    $mesLab->thaw();
    $mesLab->show();

    my $meshbox = Gtk::VBox->new(0, 20);
    $meshbox->pack_start($mesLab, 0, 0, 0);
    $meshbox->show();

    $messybox->add($meshbox);
    $messybox->show_now();

    # Read the XML file
    my $reader = WordNet::SenseRelate::Reader::Senseval2->new($fname);

    # Remove "Reading file... " window, && Show message box of errors, if any, && return
    $messybox->destroy();
    if(!defined $reader || !ref($reader))
    {
        &showMessageBox("Error", "Error reading XML file.");
        return;
    }

    return $reader;
}

# Refresh the GUI with new data
sub refreshGUI
{
    my $reader = shift;
    return if(!defined $reader);

    # Freeze the CList.
    $clist->freeze();

    # Empty the CList.
    $clist->clear();

    # Iterate through the data structure and
    # add the entries to the CList.
    foreach my $index (0 .. $reader->instanceCount() - 1)
    {
        my $theInst = $reader->instance($index);
        my $theID = "";
        $theID = $theInst->{id} if(defined $theInst->{id});
        my $theLexelt = ""; 
        $theLexelt = $theInst->{lexelt} if(defined $theInst->{lexelt});
        my $tPOS = "NOUN"; 
        $tPOS = $theInst->{targetpos} if(defined $theInst->{targetpos});
        $tPOS = $posMap{$theInst->{targetpos}} if(defined $theInst->{targetpos} && $theInst->{targetpos} =~ /^[nvar]$/);
        my $answerkey = "";
        $answerkey = $theInst->{answer} if(defined $theInst->{answer});
        $clist->append($theID, $theLexelt, $tPOS, $answerkey);
    }

    # Thaw the CList for the changes to suddenly
    # show up on screen.
    $clist->thaw();    
}

# Display the instance data of selected row
sub displayInstanceData
{
    my @selected = $clist->selection();
    return if(scalar(@selected) <= 0);
    my $index = shift(@selected);
    $textBox->freeze();

    my $selectedInstance = $instanceData->instance($index);
    return if(!defined $selectedInstance);

    # Delete all the text in there.
    my $tLength = $textBox->get_length();
    $textBox->set_point($tLength);
    $textBox->backward_delete($tLength);

    foreach my $textindex (0 .. scalar(@{$selectedInstance->{text}}) - 1)
    {
        my $background = undef;
        $background = $esColor if($textindex == $selectedInstance->{head});
        my $printedStuff = $selectedInstance->{text}->[$textindex];
        $printedStuff =~ s/^\s+//;
        $printedStuff =~ s/\s+$//;
        $printedStuff =~ s/\[[^\]]*\]//g;
        $textBox->insert(undef, undef, $background, $printedStuff);
        $textBox->insert(undef, undef, undef, " ");
    }

    $textBox->thaw();

    my $daID = "";
    $daID = $selectedInstance->{id} if(defined $selectedInstance->{id});
    my $daLexelt = "";
    $daLexelt = $selectedInstance->{lexelt} if(defined $selectedInstance->{lexelt});
    my $daAns = "";
    $daAns = $selectedInstance->{answer} if(defined $selectedInstance->{answer});
    my $daPos = "NOUN";
    $daPos = $selectedInstance->{targetpos} if(defined $selectedInstance->{targetpos});
    $daPos = $posMap{$selectedInstance->{targetpos}} if(defined $selectedInstance->{targetpos} && $selectedInstance->{targetpos} =~ /^[nvar]$/);
    $inLabel->set_text("Instance ID: $daID\nLexical Element: $daLexelt\nAnswer: $daAns\nTarget part-of-speech: $daPos");
}

# Disambiguate the current instance
sub disambiguateInstance
{
    my @selected = $clist->selection();
    return if(scalar(@selected) <= 0);
    my $index = shift(@selected);

    my $traceWindow = Gtk::Window->new('dialog');
    $traceWindow->set_usize(500, 400);
    $traceWindow->set_policy(0, 0, 1);
    # $traceWindow->set_resizable(0);
    $traceWindow->set_title("Trace Information: Disambiguating Instance...");
    $traceWindow->set_position('center');
    $traceWindow->border_width(0);
    $traceWindow->set_modal(1);

    my $traceBox = Gtk::Text->new();
    $traceBox->set_usize(480, 360);
    $traceBox->set_editable(0);
    $traceBox->set_word_wrap(1);
    $traceBox->set_line_wrap(1);
    $traceBox->show();

    my $tracebar = Gtk::VScrollbar->new($traceBox->vadj);
    $tracebar->show();

    my $traceHBox = Gtk::HBox->new(0, 0);
    $traceHBox->pack_end($tracebar, 0, 0, 0);
    $traceHBox->pack_end($traceBox, 0, 0, 0);
    $traceHBox->show();

    my $closeButton = Gtk::Button->new("Close");
    $closeButton->signal_connect('clicked', sub{ $traceWindow->destroy(); });
    $closeButton->set_sensitive(0);
    $closeButton->show();

    my $closeTable = Gtk::Table->new(1, 7);
    $closeTable->attach_defaults($closeButton, 3, 4, 0, 1);
    $closeTable->show();

    my $traceVBox = Gtk::VBox->new();
    $traceVBox->pack_start($traceHBox, 0, 0, 0);
    $traceVBox->pack_start($closeTable, 0, 0, 0);
    $traceVBox->show();

    $traceWindow->add($traceVBox);
    $traceWindow->show_now();

    my ($sense, $errorStr) = $targetWord->disambiguate($instanceData->instance($index));
    $traceBox->insert(undef, undef, undef, $targetWord->getTraceString());
    if(!defined $sense)
    {
        $traceWindow->destroy();
        &showMessageBox("Error", $errorStr);
        return;
    }

    $outLabel->set_text("Selected sense: $sense");

    $outText->freeze();
    # Delete all the text in there.
    my $tLength = $outText->get_length();
    $outText->set_point($tLength);
    $outText->backward_delete($tLength);
    $outText->insert(undef, undef, undef, $wntools->{wn}->querySense($sense, "glos"));
    $outText->thaw();

    $traceWindow->set_title("Trace Information");
    $closeButton->set_sensitive(1);
    $closeButton->show();
    $traceWindow->show();
}

# General purpose message box
sub showMessageBox
{
    my $title = shift;
    my $message = shift;
    return if(!defined $title || !defined $message);
    my $mbox = Gtk::Window->new('dialog');
    $mbox->set_usize(400, 100);
    $mbox->set_policy(0, 0, 1);
    # $mbox->set_resizable(0);
    $mbox->set_title($title);
    $mbox->set_position('center');
    $mbox->border_width(0);
    $mbox->set_modal(1);

    my $mesLabel = Gtk::Label->new($message);
    $mesLabel->show();

    my $okButton = Gtk::Button->new("Ok");
    $okButton->signal_connect('clicked', sub{ $mbox->destroy(); });
    $okButton->show();

    my $okTable = Gtk::Table->new(1, 5, 1);
    $okTable->attach_defaults($okButton, 2, 3, 0, 1);
    $okTable->show();

    my $mesBox = Gtk::VBox->new(0, 20);
    $mesBox->pack_start($mesLabel, 0, 0, 0);
    $mesBox->pack_start($okTable, 0, 0, 0);
    $mesBox->show();

    $mbox->add($mesBox);
    $mbox->show();
}

# Create read setup options dialog
sub setupDialog
{
    # Create the setup window
    my $setupWindow = Gtk::Window->new('dialog');
    $setupWindow->set_usize(600, 350);
    $setupWindow->set_policy(0, 0, 1);
    $setupWindow->set_title("WordNet::SenseRelate::TargetWord Setup: Select Modules");
    $setupWindow->set_position('center');
    $setupWindow->border_width(0);
    $setupWindow->set_modal(1);

    my $prelist = Gtk::CList->new_with_titles("Preprocess Modules");
    $prelist->set_selection_mode('multiple');
    $prelist->set_column_justification(0, 'center');
    $prelist->set_column_width(0, 250);
    $prelist->column_titles_passive();
    foreach my $mod (@{$moduleNames{'PREPROCESS'}})
    {
        $prelist->append($mod);
    }
    $prelist->show();
    
    # Create a Scrolled Window for CList
    my $scroll = Gtk::ScrolledWindow->new();
    $scroll->set_policy('automatic', 'always');
    $scroll->set_usize(300, 150);
    $scroll->add($prelist);
    $scroll->show();
    
    my $postlist = Gtk::CList->new_with_titles("Postprocess Modules");
    $postlist->set_selection_mode('extended');
    $postlist->set_column_justification(0, 'center');
    $postlist->set_column_width(0, 70);
    $postlist->column_titles_passive();
    foreach my $mod (@{$moduleNames{'POSTPROCESS'}})
    {
        $postlist->append($mod);
    }
    $postlist->show();
    
    # Create a Scrolled Window for CList
    my $scroll2 = Gtk::ScrolledWindow->new();
    $scroll2->set_policy('automatic', 'always');
    $scroll2->set_usize(300,150);
    $scroll2->add($postlist);
    $scroll2->show();

    # Create HBox for clist-window and text-vbox
    my $modHBox = Gtk::HBox->new(0, 0);
    $modHBox->pack_start($scroll, 0, 0, 0);
    $modHBox->pack_start($scroll2, 1, 1, 0);
    $modHBox->show();

    my $conlist = Gtk::CList->new_with_titles("Context Modules");
    $conlist->set_selection_mode('browse');
    $conlist->set_column_justification(0, 'center');
    $conlist->column_titles_passive();
    foreach my $mod (@{$moduleNames{'CONTEXT'}})
    {
        $conlist->append($mod);
    }
    $conlist->show();
    
    # Create a Scrolled Window for CList
    my $scroll3 = Gtk::ScrolledWindow->new();
    $scroll3->set_policy('automatic', 'always');
    $scroll3->set_usize(300, 150);
    $scroll3->add($conlist);
    $scroll3->show();
    
    my $algolist = Gtk::CList->new_with_titles("Algorithm Modules");
    $algolist->set_selection_mode('browse');
    $algolist->set_column_justification(0, 'center');
    $algolist->column_titles_passive();
    foreach my $mod (@{$moduleNames{'ALGORITHM'}})
    {
        $algolist->append($mod);
    }
    $algolist->show();
    
    # Create a Scrolled Window for CList
    my $scroll4 = Gtk::ScrolledWindow->new();
    $scroll4->set_policy('automatic', 'always');
    $scroll4->set_usize(300,150);
    $scroll4->add($algolist);
    $scroll4->show();

    # Create HBox for clist-window and text-vbox
    my $modHBox2 = Gtk::HBox->new(0, 0);
    $modHBox2->pack_start($scroll3, 0, 0, 0);
    $modHBox2->pack_start($scroll4, 1, 1, 0);
    $modHBox2->show();    

    my $canButton = Gtk::Button->new("Cancel");
    $canButton->show();
    $canButton->signal_connect('clicked', sub{ $setupWindow->destroy(); });
    my $nextButton = Gtk::Button->new("Next >");
    $nextButton->show();
    $nextButton->signal_connect('clicked', \&setupModuleOptions, $setupWindow, $prelist, $postlist, $conlist, $algolist);

    my $cTable = Gtk::Table->new(1, 5);
    $cTable->attach_defaults($canButton, 1, 2, 0, 1);
    $cTable->attach_defaults($nextButton, 3, 4, 0, 1);
    $cTable->show();

    # Create VBox for clist-window and text-vbox
    my $modVBox = Gtk::VBox->new(0, 0);
    $modVBox->pack_start($modHBox, 0, 0, 0);
    $modVBox->pack_start($modHBox2, 1, 1, 0);
    $modVBox->pack_end($cTable, 0, 0, 0);
    $modVBox->show();

    $setupWindow->add($modVBox);
    $setupWindow->show();
}

sub setupModuleOptions
{
    my $widget = shift;
    my $prevWindow = shift;
    my $prelist = shift;
    my $postlist = shift;
    my $conlist = shift;
    my $algolist = shift;

    my @preMods = ();
    my @postMods = ();
    my @conMod = ();
    my @algoMod = ();
    my %codes = ('i' => 'Integer',
                 'f' => 'File Name',
                 's' => 'String',
                 'm' => 'Module Name');

    @preMods = $prelist->selection() if(defined $prelist);
    @postMods = $postlist->selection() if(defined $postlist);
    @conMod = $conlist->selection() if(defined $conlist);
    @algoMod = $algolist->selection() if(defined $algolist);

    $prevWindow->destroy();
    
    my $setupWindow = Gtk::Window->new('dialog');
    $setupWindow->set_usize(700, 350);
    $setupWindow->set_policy(0, 0, 1);
    $setupWindow->set_title("WordNet::SenseRelate::TargetWord Setup: Select Module Options");
    $setupWindow->set_position('center');
    $setupWindow->border_width(0);
    $setupWindow->set_modal(1);
    
    my $modVBox = Gtk::VBox->new(0, 0);

    my %textboxHash;
    my $moduleList = {preprocess => [],
                      postprocess => [],
                      context => undef,
                      algorithm => undef};

    foreach my $presel (@preMods)
    {
        my $mName = $moduleNames{'PREPROCESS'}->[$presel];
        push(@{$moduleList->{preprocess}}, $mName);
        foreach my $oName (keys(%{$moduleOptions{$mName}}))
        {
            my $theCode = $moduleOptions{$mName}->{$oName};
            my ($typo, $reqd, $defval) = split(/!!/, $theCode);
            my $label = Gtk::Label->new("$mName   $oName   ($codes{$typo}, ".(($reqd)?(""):("Not "))."Required) ");
            $label->show();
            my $tbox = Gtk::Entry->new();
            $tbox->set_text($defval) if(defined $defval && $defval ne "");
            $tbox->show();
            $textboxHash{$mName}{$oName} = $tbox;
            my $hhbox = Gtk::HBox->new(0, 0);
            $hhbox->pack_start($label, 0, 0, 0);
            $hhbox->pack_end($tbox, 1, 1, 0);
            $hhbox->show();
            $modVBox->pack_start($hhbox, 0, 0, 0);
        }
    }

    foreach my $postsel (@postMods)
    {
        my $mName = $moduleNames{'POSTPROCESS'}->[$postsel];
        push(@{$moduleList->{postprocess}}, $mName);
        foreach my $oName (keys(%{$moduleOptions{$mName}}))
        {
            my $theCode = $moduleOptions{$mName}->{$oName};
            my ($typo, $reqd, $defval) = split(/!!/, $theCode);
            my $label = Gtk::Label->new("$mName   $oName   ($codes{$typo}, ".(($reqd)?(""):("Not "))."Required) ");
            $label->show();
            my $tbox = Gtk::Entry->new();
            $tbox->set_text($defval) if(defined $defval && $defval ne "");
            $tbox->show();
            $textboxHash{$mName}{$oName} = $tbox;
            my $hhbox = Gtk::HBox->new(0, 0);
            $hhbox->pack_start($label, 0, 0, 0);
            $hhbox->pack_end($tbox, 1, 1, 0);
            $hhbox->show();
            $modVBox->pack_start($hhbox, 0, 0, 0);
        }
    }

    my $consel = shift(@conMod);
    if(defined $consel && $consel ne "")
    {
        my $mName = $moduleNames{'CONTEXT'}->[$consel];
        $moduleList->{context} = $mName;
        foreach my $oName (keys(%{$moduleOptions{$mName}}))
        {
            my $theCode = $moduleOptions{$mName}->{$oName};
            my ($typo, $reqd, $defval) = split(/!!/, $theCode);
            my $label = Gtk::Label->new("$mName   $oName   ($codes{$typo}, ".(($reqd)?(""):("Not "))."Required) ");
            $label->show();
            my $tbox = Gtk::Entry->new();
            $tbox->set_text($defval) if(defined $defval && $defval ne "");
            $tbox->show();
            $textboxHash{$mName}{$oName} = $tbox;
            my $hhbox = Gtk::HBox->new(0, 0);
            $hhbox->pack_start($label, 0, 0, 0);
            $hhbox->pack_end($tbox, 1, 1, 0);
            $hhbox->show();
            $modVBox->pack_start($hhbox, 0, 0, 0);
        }
    }

    my $algosel = shift(@algoMod);
    if(defined $algosel && $algosel ne "")
    {
        my $mName = $moduleNames{'ALGORITHM'}->[$algosel];
        $moduleList->{algorithm} = $mName;
        foreach my $oName (keys(%{$moduleOptions{$mName}}))
        {
            my $theCode = $moduleOptions{$mName}->{$oName};
            my ($typo, $reqd, $defval) = split(/!!/, $theCode);
            my $label = Gtk::Label->new("$mName   $oName   ($codes{$typo}, ".(($reqd)?(""):("Not "))."Required) ");
            $label->show();
            my $tbox = Gtk::Entry->new();
            $tbox->set_text($defval) if(defined $defval && $defval ne "");
            $tbox->show();
            $textboxHash{$mName}{$oName} = $tbox;
            my $hhbox = Gtk::HBox->new(0, 0);
            $hhbox->pack_start($label, 0, 0, 0);
            $hhbox->pack_end($tbox, 1, 1, 0);
            $hhbox->show();
            $modVBox->pack_start($hhbox, 0, 0, 0);
        }
    }

    my $canButton = Gtk::Button->new("Cancel");
    $canButton->show();
    $canButton->signal_connect('clicked', sub{ $setupWindow->destroy(); });
    my $nextButton = Gtk::Button->new("Next >");
    $nextButton->show();
    $nextButton->signal_connect('clicked', \&getOptionsFromFields, $setupWindow, $moduleList, \%textboxHash);

    my $cTable = Gtk::Table->new(1, 5);
    $cTable->attach_defaults($canButton, 1, 2, 0, 1);
    $cTable->attach_defaults($nextButton, 3, 4, 0, 1);
    $cTable->show();

    # Create VBox for clist-window and text-vbox
    $modVBox->pack_end($cTable, 0, 0, 0);
    $modVBox->show();

    $setupWindow->add($modVBox);
    $setupWindow->show();
}

sub getOptionsFromFields
{
    my $widget = shift;
    my $prevWindow = shift;
    my $modList = shift;
    my $textList = shift;
    
    $modList->{preprocessconfig} = [];
    $modList->{postprocessconfig} = [];
    $modList->{contextconfig} = undef;
    $modList->{algorithmconfig} = undef;
    $modList->{wntools} = $wntools;

    foreach my $premod ($modList->{preprocess})
    {
        my $modOptions = {};
        if(exists $textList->{$premod})
        {
            foreach my $theopt (keys %{$textList->{$premod}})
            {
                my $theText = $textList->{$premod}->{$theopt}->get_text();
                $modOptions->{$theopt} = $theText if(defined $theText && $theText ne "");
            }
        }
        push(@{$modList->{preprocessconfig}}, $modOptions);
    }

    foreach my $premod ($modList->{postprocess})
    {
        my $modOptions = {};
        if(exists $textList->{$premod})
        {
            foreach my $theopt (keys %{$textList->{$premod}})
            {
                my $theText = $textList->{$premod}->{$theopt}->get_text();
                $modOptions->{$theopt} = $theText if(defined $theText && $theText ne "");
            }
        }
        push(@{$modList->{postprocessconfig}}, $modOptions);
    }

    my $conmod = $modList->{context};
    if(defined $conmod && $conmod ne "")
    {
        my $modOptions = {};
        if(exists $textList->{$conmod})
        {
            foreach my $theopt (keys %{$textList->{$conmod}})
            {
                my $theText = $textList->{$conmod}->{$theopt}->get_text();
                $modOptions->{$theopt} = $theText if(defined $theText && $theText ne "");
            }
        }
        $modList->{contextconfig} = $modOptions;
    }
    
    $conmod = $modList->{algorithm};
    if(defined $conmod && $conmod ne "")
    {
        my $modOptions = {};
        if(exists $textList->{$conmod})
        {
            foreach my $theopt (keys %{$textList->{$conmod}})
            {
                my $theText = $textList->{$conmod}->{$theopt}->get_text();
                $modOptions->{$theopt} = $theText if(defined $theText && $theText ne "");
            }
        }
        $modList->{algorithmconfig} = $modOptions;
    }

    $prevWindow->destroy();

    # Load WordNet::SenseRelate::TargetWord...
    # Exit with warning message, if unable to load...
    # Show "Loading TargetWord... " window
    my $messybox = Gtk::Window->new('dialog');
    $messybox->set_usize(400, 100);
    $messybox->set_policy(0, 0, 1);
    # $messybox->set_resizable(0);
    $messybox->set_title("Information: Reloading WordNet::SenseRelate::TargetWord... Please Wait.");
    $messybox->set_position('center');
    $messybox->border_width(0);
    $messybox->set_modal(1);

    #my $mesLab = Gtk::Label->new("Reading XML file. Please Wait.");
    #$mesLab->set_justify('left');
    #$mesLab->show();

    my $mesLab = Gtk::Text->new();
    $mesLab->set_usize(200, 50);
    $mesLab->set_editable(0);
    $mesLab->set_word_wrap(1);
    $mesLab->set_line_wrap(1);
    $mesLab->freeze();
    $mesLab->insert(undef, undef, undef, "Reloading WordNet::SenseRelate::TargetWord. Please Wait.");
    $mesLab->thaw();
    $mesLab->show();

    my $meshbox = Gtk::VBox->new(0, 20);
    $meshbox->pack_start($mesLab, 0, 0, 0);
    $meshbox->show();

    $messybox->add($meshbox);
    $messybox->show_now();

    my ($newTargetWord, $newError) = WordNet::SenseRelate::TargetWord->new($modList, 1);

    # Remove "Reloading... " window, && Show message box of errors, if any, && return
    $messybox->destroy();
    if(!defined $newTargetWord || !ref($newTargetWord))
    {
        &showMessageBox("Error", "Error loading module: $newError");
        return;
    }

    $targetWord = $newTargetWord;
}

# Create Help->About window
sub showAbout
{
    # Create the about window
    my $about = Gtk::Window->new('dialog');
    $about->set_usize(360, 250);
    $about->set_policy(0, 0, 1);
    $about->set_title("About WordNet::SenseRelate::TargetWord");
    $about->set_position('center');
    $about->border_width(0);
    $about->set_modal(1);

    # Create a TextBox
    my $aboutText = Gtk::Text->new();
    $aboutText->set_editable(0);
    $aboutText->set_word_wrap(1);
    $aboutText->set_line_wrap(1);
    $aboutText->set_usize(360, 220);
    my $name = "-misc-fixed-bold-r-normal--15-140-75-75-c-90-iso8859-1";
    my $fixed_font = Gtk::Gdk::Font->load($name);
    $aboutText->insert($fixed_font, undef, undef, "\n    WordNet::SenseRelate::TargetWord\n\n");
    $name = "-misc-fixed-medium-r-normal--14-130-75-75-c-70-iso8859-1";
    $fixed_font = Gtk::Gdk::Font->load($name);
    $aboutText->insert($fixed_font, undef, undef, "                       v$VERSION\n");
    $aboutText->insert($fixed_font, undef, undef, "                 Copyright (c) 2005\n\n");
    $aboutText->insert($fixed_font, undef, undef, "                Siddharth Patwardhan\n");
    $aboutText->insert($fixed_font, undef, undef, "                  sidd\@cs.utah.edu\n\n");
    $aboutText->insert($fixed_font, undef, undef, "                    Ted Pedersen\n");
    $aboutText->insert($fixed_font, undef, undef, "                 tpederse\@d.umn.edu\n\n");
    $aboutText->insert($fixed_font, undef, undef, "                 Satanjeev Banerjee\n");
    $aboutText->insert($fixed_font, undef, undef, "                banerjee+\@cs.cmu.edu\n");
    $aboutText->show();

    # Create a close Button
    my $aboutButton = Gtk::Button->new("Close");
    $aboutButton->signal_connect('clicked', sub{ $about->destroy(); });
    $aboutButton->show();
    
    # Create a VBox
    my $aboutVBox = Gtk::VBox->new(0, 5);
    $aboutVBox->pack_start($aboutText, 0, 0, 0);
    $aboutVBox->pack_start($aboutButton, 0, 0, 0);
    $aboutVBox->show();

    # Display it
    $about->add($aboutVBox);
    $about->show();
}

# Show startup warnings
sub displayStartupWarnings
{
    return if(scalar(@_) <= 0);
    my $mbox = Gtk::Window->new('dialog');
    $mbox->set_usize(400, 150);
    $mbox->set_policy(0, 0, 1);
    # $mbox->set_resizable(0);
    $mbox->set_title("Warning(s)");
    $mbox->set_position('center');
    $mbox->border_width(0);
    $mbox->set_modal(1);

    my $message = "Warning(s):\n".(join("\n", @_))."\n";
    my $mesLabel = Gtk::Label->new($message);
    $mesLabel->show();

    my $okButton = Gtk::Button->new("Ok");
    $okButton->signal_connect('clicked', sub{ $mbox->destroy(); });
    $okButton->show();

    my $okTable = Gtk::Table->new(1, 5, 1);
    $okTable->attach_defaults($okButton, 2, 3, 0, 1);
    $okTable->show();

    my $mesBox = Gtk::VBox->new(0, 20);
    $mesBox->pack_start($mesLabel, 0, 0, 0);
    $mesBox->pack_start($okTable, 0, 0, 0);
    $mesBox->show();

    $mbox->add($mesBox);
    $mbox->show();
}

# Subroutine that reads the options file
sub readConfigFile
{
    my $fname = shift;

    if(!open(CONFIG, "$fname"))
    {
        &askHelp("disamb-gui.pl: Unable to open specified configuration file.");
        return undef;
    }
    my $line = <CONFIG>;
    $line =~ s/[\r\f\n]//;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    if ($line !~ /^WordNet::SenseRelate::TargetWord$/)
    {
        &askHelp("disamb.pl: File format error (in header) in config file.");
        return undef;
    }
    my $struct  = {};
    my $section = "";
    my $modname = "";
    my $modata  = undef;

    while ($line = <CONFIG>)
    {
        $line =~ s/[\r\f\n]//;
        $line =~ s/\#.*//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        if ($line =~ /\[SECTION:([^\]]*)\]/)
        {
            $section = $1;
            $struct->{$section} = []
              if (   defined $section
                  && $section ne ""
                  && !exists($struct->{$section}));
        }
        elsif ($line =~ /\[START\s+([^\]]+)\]/)
        {
            return undef if (!defined $section || $section eq "");
            $modname = $1;
            $modata  = {};
        }
        elsif ($line =~ /\[END\]/)
        {
            return undef
              if (   !defined $section
                  || $section eq ""
                  || !defined $modname
                  || $modname eq "");
            return undef if (!defined $modata);
            $modata->{'name'} = $modname;
            push(@{$struct->{$section}}, $modata);
            $modname = "";
            $modata  = undef;
        }
        elsif ($line =~ /([^=]+)\s*=\s*([^=]+)/)
        {
            return undef
              if (   !defined $section
                  || !defined $modname
                  || $section eq ""
                  || $modname eq "");
            $modata->{$1} = $2;
        }
        elsif ($line ne "")
        {
            return undef;
        }
    }
    close(CONFIG);

    return $struct;
}

# function to output help messages for this program
sub printHelp
{
    print "Performs Word Sense Disambiguation on Senseval-2 lexical sample data\n";
    print "(graphical interface to WordNet::SenseRelate::TargetWord).\n";
    print "Usage: disamb-gui.pl [ [--config FILE] [--wnpath WNPATH] [XMLFILE] | --help | --version]\n";
    print "--config         Specifies a configuration file (FILE) to set up the\n";
    print "                 various configuration options.\n";
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
    my $message = shift;
    push(@warnings, $message) if (defined $message && $message ne "");
}

# Subroutine to print the version information
sub printVersion
{
    print "disamb-gui.pl version $VERSION\n";
    print "Copyright (c) 2005 Satanjeev Banerjee, Ted Pedersen and Siddharth Patwardhan.\n";
}

__END__


=head1 NAME

disamb-gui.pl - graphical interface for WordNet::SenseRelate::TargetWord, a Word Sense Disambiguation 
module.

=head1 SYNOPSIS

disamb-gui.pl [ [--config FILE] [--wnpath WNPATH] [XMLFILE] | --help | --version ]

=head1 DESCRIPTION

This program is a graphical interface to the WordNet::SenseRelate::TargetWord Word Sense Disambiguation
module. It takes as input a Senseval-2 formatted input file and disambiguated each instance specified in
file. The module is highly configurable. The user is allowed to choose different preprocessing and
postprocessing tasks for the data, the dismabiguation algorithm and the context selection algorithm.

=head1 OPTIONS

Usage: disamb-gui.pl [ [--config FILE] [--wnpath WNPATH] [XMLFILE] | --help | --version ]

B<--config>=I<FILE>
    Specifies a configuration file (FILE) to set up the various configuration options.

B<--wnpath>=I<WNPATH>
    WNPATH specifies the path of the WordNet data files. Ordinarily, this path is 
    determined from the $WNHOME environment variable. But this option overides this
    behavior.

B<--help>
    Displays this help screen.

B<--version>
    Displays version information.

=head1 AUTHORS

 Siddharth Patwardhan <sidd at cs.utah.edu>

 Ted Pedersen <tpederse at d.umn.edu>

 Satanjeev Banerjee <banerjee+ at cs.cmu.edu>

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
