# Please include this text with any bug reports
# $Id: userfile.pm 12792 2014-07-10 08:04:48Z brain $
# =============================================

use strict;
use Digest::SHA  qw(sha1 sha1_hex sha1_base64);
use POSIX qw(ceil floor);

sub init {
        die("This module may not be loaded from the configuration file");
}

sub checkuserfile {
	srand;
	my $masterkey = floor(rand(9999999)+1);
	my ($userfile) = @_;
	my $failopen = 0;
	open(USERFILE,"<$userfile") or $failopen = 1;
	if ($failopen) {
		print "Failed to open userfile '$userfile', starting in first-use mode.\n";
		print "To create an owner account on the bot, please message it\n";
		print "the initialization command, as follows:\n\n";
		print "/msg <bot nick> init-$masterkey\n";
		return $masterkey;
	} else {
		close USERFILE;
		return 0;
	}
}

sub loaduserfile {
	%main::users = ();
	my ($userfile) = @_;
	lprint("Loading userfile...") if $main::debug;
	my $failopen = 0;
	my $line = "";
	open(USERFILE,"<$userfile") or $failopen = 1;
	if (!$failopen) {
		while (chomp($line = <USERFILE>)) {
			$line = trim($line);
			# read a line from the userfile
			my ($handle,$type,$data) = split(' ',$line,3);
			if ($type eq "FLAG") {
				my ($network,$channel,$flaglist) = split(' ',$data,3);
				$main::users{$handle}{FLAGS}{$network}{lc($channel)} .= "$flaglist ";
				lprint("Added flags '$flaglist' to $handle on $network channel $channel") if $main::debug;
			} else {
				if ($type eq "PASS") {
					$main::users{$handle}{$type}  = "$data ";
				} else {
					$main::users{$handle}{$type} .= "$data ";
				}
				lprint("Append data type $type to user $handle, data string is now '$data'") if $main::debug;
			}
 		}
		close(USERFILE);
	}
}

sub saveuserfile {
	my ($userfile) = @_;
	lprint("Saving userfile...") if $main::debug;
	my $failopen = 0;
	open(USERFILE,">$userfile") or $failopen = 1;
	if (!$failopen) {
		foreach my $user (keys %main::users) {
			# first save global flags, and globalchannel flags
			print USERFILE "$user FLAG _ _ $main::users{$user}{FLAGS}{_}{_}\n" if defined $main::users{$user}{FLAGS}{_}{_};
			print USERFILE "$user DESC $main::users{$user}{DESC}\n" if defined $main::users{$user}{DESC};
			print USERFILE "$user PASS $main::users{$user}{PASS}\n" if defined $main::users{$user}{PASS};
			# modules can save userfile sections for users to the userfile if the section name is the same as
			# their module name. If the module is unloaded then their information is lost when it comes to
			# saving the userfile!!!
			foreach my $module (@main::modules) {
				print USERFILE "$user $module $main::users{$user}{$module}\n" if defined $main::users{$user}{$module};
			}
			my @hostlist = split(' ',trim($main::users{$user}{HOST}));
			foreach my $host (@hostlist) {
				print USERFILE "$user HOST $host\n";
			}
			my @chans = split(' ',$main::config{_}{channels});
			foreach my $channelname (@chans) {
				print USERFILE "$user FLAG _ $channelname $main::users{$user}{FLAGS}{_}{lc($channelname)}n" if defined $main::users{$user}{FLAGS}{_}{lc($channelname)};
			}
			foreach my $nid (keys %main::config) {
				my @chans = split(' ',$main::config{$nid}{channels});
				if ($nid eq "_") { @chans = () };
				foreach my $channelname (@chans) {
					print USERFILE "$user FLAG $nid $channelname $main::users{$user}{FLAGS}{$nid}{lc($channelname)}\n" if defined $main::users{$user}{FLAGS}{$nid}{lc($channelname)};
				}
			}

		}
		lprint("Done saving user file") if $main::debug;
		close(USERFILE);
	}
}

sub userexists {
	return defined($main::users{$_[0]}{PASS});
}

sub comparepassword {
	lprint("Compare passes: '" . trim($main::users{$_[0]}{PASS}) . "' to '" . sha1_base64($_[1]) ."'") if $main::debug;
	return (trim($main::users{$_[0]}{PASS}) eq sha1_base64($_[1]));
}

sub passwordhash {
	return sha1_base64($_[0]);
}

sub userdesc {
	return $main::users{$_[0]}{DESC};
}

# returns true if $handle has $flag on $channel

sub hasflag {
	my ($handle,$flag,$network,$channel) = @_;
	# first compile a list of flags, from the specific channel and globally
	my $flaglist = trim($main::users{$handle}{FLAGS}{_}{_} . $main::users{$handle}{FLAGS}{_}{lc($channel)} . $main::users{$handle}{FLAGS}{$network}{lc($channel)});
	lprint("Flaglist for $handle is $flaglist") if $main::debug;
	my @flags = split(' ',$flaglist);
	foreach my $cflag (@flags) {
		lprint("Compare $cflag to $flag") if $main::debug;
		if (lc($cflag) eq lc($flag)) {
			return 1;
		}
	}
	return 0;
}

# returns the first handle that matches this host

sub matcheshost {
	my ($ident,$h) = @_;
	my $host = "$ident\@$h";
	foreach my $handle (keys %main::users) {
		my $hostlist = trim($main::users{$handle}{HOST});
		my @hosts = split(' ',$hostlist);
		foreach my $chost (@hosts) {
			if ($chost =~ /^\*/) {
				$chost = wildcard_to_regexp($chost);
			}
			if ($host =~ /$chost/i) {
				return $handle;
			} 
		}
	}
	return "";

}

1;
