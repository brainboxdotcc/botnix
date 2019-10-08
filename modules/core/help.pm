# Please include this text with any bug reports
# $Id: help.pm 1899 2005-10-01 16:10:29Z brain $
# =============================================

use strict;

sub init {
        die("This module may not be loaded from the configuration file");
}

my %helpsections = 	(

				"Core Commands" => "LOGIN LOGOUT HELP PASS ADDUSER DELUSER CHPASS ADDHOST DELHOST ADDFLAGS DELFLAGS SHUTDOWN MODULES NETWORKS MATCH ADDOP ADDMASTER UPTIME",
				"Channel Commands" => "",
				"Admin Commands" => "CONFIG",

			);

my %contexthelp =	(

				"SHUTDOWN" => "Syntax: SHUTDOWN\nShuts down the bot and saves the userfile.",
				"LOGIN" => "Syntax: LOGIN <password>\nAllows you to log into the bot.",
				"LOGOUT" => "Syntax: LOGOUT\nLogs you out of the bot.",
				"PASS" => "Syntax: PASS <old password> <new password>\nSyntax: PASS <new password>\nChanges your password. If you are already logged in\nto the bot, you need only provide the new password, otherwise you must provide both your\nold and new passwords.",
				"HELP" => "Syntax: HELP [topic]\nProvides context sensitive help.",
				"ADDUSER" => "Syntax: ADDUSER <handle> <description>\nAdds a new user with no hosts, flags or password.",
				"DELUSER" => "Syntax: DELUSER <handle>\nDeletes a user.",
				"CHPASS" => "Syntax: CHPASS <handle> <new password>\nChanges a user's password",
				"ADDHOST" => "Syntax: ADDHOST <handle> <host regexp>\nAdds a host regexp to a user ()",
				"DELHOST" => "Syntax: DELHOST <handle> <host regexp>\nDeletes a host regexp from a user ()",
				"ADDFLAGS" => "Syntax: ADDFLAGS <handle> <network> <#channel> <flags>\nAdds flags to a user. Use a * in the network\nfield to make the flags global across all networks,\nor a * in both fields to make the flags\nglobal in all situations (e.g. with the\n'owner' flag)",
				"DELFLAGS" => "Syntax: DELFLAGS <handle> <network> <#channel> <flags>\nDeletes flags from a user. Use a * in the network\nfield to make the flags global across all networks,\nor a * in both fields to make the\nflags global in all situations (e.g. with the\n'owner' flag)",
				"MODULES" => "Syntax: MODULES\nShows a list of all loaded modules.",
				"NETWORKS" => "Syntax: NETWORKS\nShows a list of all networks and their states.",
				"MATCH" => "Syntax: MATCH <regexp>\nShows information for all users matching\na regular expression",
				"ADDOP" => "Syntax: ADDOP <nick> <channel>\nAdds a user as a channel operator, automatically\ncalculating hosts and generating a random password.",
				"ADDMASTER" => "Syntax: ADDMASTER <nick> <channel>\nAdds a user as a channel master, automatically\ncalculating a hostmask and creating a random password.",
				"UPTIME" => "Syntax: UPTIME\nShows the uptime of the bot.",
				"CONFIG" => "Syntax: CONFIG DUMP|SET <key> <variable> <value>|DEL <key> [variable]\nSet or get configuration options at runtime",

			);

sub build_help_text {
	my ($nid,$nick,$ident,$host,$params,$handle) = @_;
	my @helplist = ("\002BotNix version $main::VERSION\002"," ");
	if ((!defined $handle) || ($handle eq "")) {
		return ("You must log in to view the help text.","Please use /msg $main::netid{$nid}{nick} login <your password>");
	}
	if ($params ne "") {
		$params = uc($params);
		if (defined $contexthelp{$params}) {
			return split('\n',"\002$params\002\n$contexthelp{$params}");
		}
		return ("Unknown help topic.");
	}
	foreach my $helpkey (sort keys %helpsections) {
		if (trim($helpsections{$helpkey}) ne "") {
			push @helplist, "\002$helpkey\002";
			my @commandlist = split(' ',trim($helpsections{$helpkey}));
			my $line = "";
			foreach my $command (sort @commandlist) {
				$line .= sprintf("%-15s",$command);
				if (length($line) > 55) {
					push @helplist, $line;
					$line = "";
				}
			}
			if (($line ne "") && ($line ne "    ")) {
				push @helplist, $line;
			}
			$line = "    ";
		}
	}
	return @helplist;
}

sub add_context_help {
	my ($subject,$text) = @_;
	$contexthelp{$subject} = $text;
}

sub del_context_help {
	my ($subject) = @_;
	delete $contexthelp{$subject};
}

sub add_help_section {
	my ($section,@commands) = @_;
	my $list = CORE::join(' ',@commands);
	my $success = !defined $helpsections{"$section"};
	if ($success) {
		$helpsections{"$section"} = $list;
		return 1;
	}
	return 0;
}

sub del_help_section {
	my ($section) = @_;
	my $success = defined $helpsections{"$section"};
	delete $helpsections{"$section"};
	return $success;
}

sub add_help_commands {
	my ($section,@commands) = @_;
	my $list = CORE::join(' ',@commands);
	if (defined $helpsections{"$section"}) {
		$helpsections{"$section"} .= " $list";
	}
	return defined $helpsections{"$section"};
}

sub del_help_commands {
	my ($section,@commands) = @_;
	if (!defined $helpsections{"$section"}) {
		return 0;
	}
	my $deleted = 0;
	my @newlist = ();
	my @list = split(' ',$helpsections{"$section"});
	foreach my $command (@list) {
		my $exists = 0;
		foreach my $search (@commands) {
			if (lc($command) eq lc($search)) {
				$exists = 1;
			}
		}
		if (!$exists) {
			push @newlist, $command;
		} else {
			$deleted++;
		}
	}
	$helpsections{"$section"} = CORE::join(' ',@newlist);
	return $deleted;
}

1;
