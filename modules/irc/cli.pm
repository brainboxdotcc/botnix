# Please include this text with any bug reports
# $Id: cli.pm 1836 2005-09-20 11:29:19Z brain $
# =============================================

package modules::irc::cli;

# This module acts as a frontend to the bot's commandline.
# Although the commandline guts are in the core of the bot,
# with functions such as add_command and do_command etc,
# this module is the 'presentation layer' which allows users
# to interact with it directly from IRC. It is abstracted from
# the core to allow easy removal in case of vulnerability or
# security enhancements.
#
# Similar calls to the commandline interpreter could be used
# to (for example) write an on-console commandline.

my $allow_in_channel = 0;
my $allow_in_message = 0;
my %nocommands =();

sub init {
	my ($self) = @_;
}

sub implements {
        my @functions = ("before_configure","on_configure","on_privmsg");
        return @functions;
}

sub shutdown {
	my ($self) = @_;
}

sub before_configure {
	$allow_in_channel = 0;
	$allow_in_message = 0;
	%nocommands = ();
}

sub on_privmsg {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if (($target =~ /^[#\&]/) && ($allow_in_channel != 0)) {
		if ($text =~ /^\!/) {
			$text =~ s/^\!//;
			if (($nocommands{$network}{lc($target)} == 1) || ($nocommands{_}{lc($target)} == 1)) {
				# commands have been disabled on this channel
				return;
			}
			if ($allow_in_channel == 1) {
				handle_private_message($nid,$nick,$ident,$host,$target,$text);
			} elsif ($allow_in_channel == 2) {
				handle_private_message($nid,$nick,$ident,$host,$nick,$text);
			}
		}
	} elsif ($allow_in_message != 0) {
		handle_private_message($nid,$nick,$ident,$host,$nick,$text);
	}
}

sub handle_private_message {
        my ($nid,$nick,$ident,$host,$target,$text) = @_;
        my ($command,$params) = split(' ',$text,2);

        my @return = main::do_command($nid,$nick,$ident,$host,$command,split(' ',$params));
        foreach my $line (@return) {
                main::send_notice($nid,$target,$line);
        }
}


sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
        if ($configline =~ /^allowcommands\s+"(.+)"$/i) {
                if (($net_context ne "_") || ($chan_context ne "")) {
                        main::lprint("allowcommands command local to a network or channel on $configfile:$linenumber");
                        return 0;
                }
		my @flags = split(',',$1);
		$allow_in_channel = 0;
		$allow_in_message = 0;
		foreach my $flag (@flags) {
			if (lc(main::trim($flag)) eq "channel") {
				$allow_in_channel = 1;
			} elsif (lc(main::trim($flag)) eq "message") {
				$allow_in_message = 1;
			} elsif (lc(main::trim($flag)) eq "channelprivate") {
				$allow_in_channel = 2;
			}
		}
        } elsif ($configline =~ /^nocommands$/i) {
		if ($chan_context eq "") {
			main::lprint("nocommands command outside channel context on $configfile:$linenumber");
			return 0;
		}
		$nocommands{$net_context}{lc($chan_context)} =  1;
	}
	return 1;
}

1;
