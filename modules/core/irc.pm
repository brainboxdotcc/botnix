# Please include this text with any bug reports
# $Id: irc.pm 10545 2008-09-15 18:33:48Z brain $
# =============================================

use strict;
use Data::Dumper;
no strict 'refs';

sub init {
        die("This module may not be loaded from the configuration file");
}

require 'modules/core/help.pm';
require 'modules/core/status.pm';
require 'modules/core/mode.pm';

our %nicks = ();
our %retrynick = ();
our %received_pong = 0;

my %banned_from = ();

my %botcmdtable = (
		     "LOGIN" => \&handle_login,
                     "LOGOUT" => \&handle_logout,
                     "HELP" => \&handle_help,
                     "PASS" => \&handle_pass,
                     "ADDUSER" => \&handle_adduser,
                     "DELUSER" => \&handle_deluser,
                     "ADDHOST" => \&handle_addhost,
                     "DELHOST" => \&handle_delhost,
                     "ADDFLAGS" => \&handle_addflags,
                     "DELFLAGS" => \&handle_delflags,
                     "CHPASS" => \&handle_chpass,
                     "MODULES" => \&handle_modules,
                     "NETWORKS" => \&handle_networks,
                     "MATCH" => \&handle_match,
                     "ADDOP" => \&handle_addop,
                     "ADDMASTER" => \&handle_addmaster,
                     "SHUTDOWN" => \&handle_quit,
                     "UPTIME" => \&handle_uptime,
		     "CONFIG" => \&handle_config,
		  );

my %cmdtable = (     "PING" => \&ping,
		     "PONG" => \&pong,
                     "NOTICE" => \&notice,
                     "PRIVMSG" => \&privmsg,
                     "KICK" => \&kick,
                     "JOIN" => \&main::join,
                     "PART" => \&part,
                     "QUIT" => \&quit,
                     "NICK" => \&nick,
                     "MODE" => \&mode,
		     "ERROR" => \&splat,
                     "324" => \&grab_modes,
                     "376" => \&onconnect,
                     "422" => \&onconnect,
                     "433" => \&nick_in_use,
                     "352" => \&who,
                     "353" => \&handle_names_list,
		     "474" => \&im_banned,		# Banned from channel due to +b
		     "495" => \&im_banned,		# InspIRCd +J
		     "609" => \&im_banned,		# InspIRCd +j
                );

sub process {
	my ($nid,$line) = @_;
	my $prefix = "";
	my $command = "";
	my $params = "";
	my $nick = "";
	my $server = "";
	my $ident = "";
	my $host = "";
	if ($line =~ /^:/) {
		$line =~ /^:(.+?)\s+(\S+)\s(.+?)$/;
		$prefix = $1;
		$command = $2;
		$params = $3;
	} else {
		$line =~ /(\S+)\s+(\S+)$/;
		$prefix = $main::netid{$nid}{server};
		$command = $1;
		$params = $2;
	}
	if ($prefix =~ /!/) {
		$prefix =~ /(\S+)!(\S+)\@(\S+)/;
		$nick = $1;
		$ident = $2;
		$host = $3;
		$server = $main::netid{$nid}{server};
	} else {
		$server = $main::netid{$nid}{server};
		$nick = "";
		$ident = "";
		$host = "";
	}
	my @items = split(' ',$params);
	my $final = 0;
	my $count = 0;
	my @plist = ();
	foreach my $item (@items) {
		if (($item =~ /^:/) && (!$final)) {
			$final = 1;
			$item =~ s/^://;
		}
		if ($final) {
			$plist[$count] .= "$item ";
		} else {
			$plist[$count++] = $item;
		}
	}
	for (my $n = 0; $n < scalar(@plist); $n++) {
		$plist[$n] = trim($plist[$n]);
	}
	trigger_on_raw($nid,$server,$nick,$ident,$host,$command,@plist);
	if (defined $cmdtable{"$command"}) {
		\$cmdtable{"$command"}($nid,$server,$nick,$ident,$host,@plist);
	}
}

sub splat ($$$$$@) {
	my ($nid,$server,$nick,$ident,$host,@plist) = @_;
	lprint("Error command on $nid, calling write_fail") if $main::debug;
	write_fail($nid);
}

sub ping ($$$$$@) {
	my ($nid,$server,$nick,$ident,$host,@plist) = @_;
	writeto($nid,"PONG :$plist[0]");
}

sub pong ($$$$$@) {
	my ($nid,$server,$nick,$ident,$host,@plist) = @_;
	$main::received_pong{$nid} = 1;
	$main::netid{$nid}{lag} = time() - $main::netid{$nid}{lastping};
	if (defined $main::retrynick{$nid}) {
		delete $main::retrynick{$nid};
		writeto($nid,"NICK $main::netid{$nid}{nick}");
	}
}

sub grab_modes {
        my ($nid,$server,$nick,$ident,$host,@plist) = @_;
        # 324 botnix #botnix +tnl 19
        my $myself = shift(@plist);
        &mode($nid,$server,$myself,$ident,$host,@plist);
}


sub who ($$$$$@) {
	# 352 neuron_nix #botnix Boo ChatSpike-E265FBDA.cpe.net.cable.rogers.com kenny.chatspike.net `Boo Hr@ :0 Boo
	my ($nid,$server,$nick,$ident,$host,@plist) = @_;
	my $nref = "$nid,$plist[5]";
	my $trigger_set = ((!defined $nicks{$nref}{host}) || ($nicks{$nref}{host} eq ""));
	$nicks{$nref}{host} = $plist[3];
	$nicks{$nref}{ident} = $plist[2];
	trigger_on_set_record($nid,$plist[5],$plist[1]) if $trigger_set;
}

sub nick_in_use ($$$$$@) {
	my ($nid,$server,undef,$ident,$host,$channel,$target,$reason) = @_;
	my $nick = $main::netid{$nid}{nick};
	$nick =~ tr/eioa\-_/3104_\-/;
	$nick .= '_';
	$main::retrynick{$nid} = 1;
	writeto($nid,"NICK $nick");
}

sub onconnect ($$$$$@) {
	my ($nid,$server,$nick,$ident,$host,$channel,$target,$reason) = @_;
	my @chans = split(' ',$main::config{$nid}{channels} . $main::config{_}{channels});
	foreach my $channelname (@chans) {
		do_join($nid,$channelname);
	}
}

sub kick ($$$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$channel,$target,$reason) = @_;
        my $nref  = "$nid,$target";
	trigger_on_kick($nid,$server,$nick,$ident,$host,$target,$channel,$reason);
	lprint_directed("KICK",$nick,$nid,$target,$reason);
        # clear these for security
        $nicks{$nref}{lc($channel)}{has_ops} = 0;
        $nicks{$nref}{lc($channel)}{has_halfops} = 0;
        $nicks{$nref}{lc($channel)}{has_voice} = 0;
        $nicks{$nref}{lc($channel)}{has_founder} = 0;
        $nicks{$nref}{lc($channel)}{has_protect} = 0;
        my @chanlist = $nicks{$nref}{channels};
        my $newlist = "";
        foreach my $chan (@chanlist) {
                if (lc(trim($chan)) ne lc(trim($channel))) {
                        $newlist .= "$chan ";
                }
        }
        lprint("Users new channel list: $newlist") if $main::debug;
        $nicks{$nref}{channels} = $newlist;
        if (trim($nicks{$nref}{channels}) eq "") {
                lprint("This user has left all channels via kick, nuke it") if $main::debug;
		trigger_on_del_record($nid,$target,$channel);
                delete $nicks{$nref};
        }
	if ($target eq $main::netid{$nid}{nick}) {
		if (($main::channelflags{$nid}{lc($channel)}{rejoin} == 1) || ($main::channelflags{_}{lc($channel)}{rejoin} == 1)) {
			my %ncopy = %main::nicks;
			my $erased = 0;
			foreach my $key (keys %ncopy) {
				my ($thisnet,$thisnick) = split(',',$key);
				if ((is_on_channel($thisnick,$thisnet,$channel)) && ($thisnet eq $nid)) {
					&part($thisnet,$main::nicks{$key}{server},$thisnick,$main::nicks{$key}{ident},$main::nicks{$key}{shost},$channel,undef,1);
					$erased++;
				}
			}
			lprint("*** Rejoining $channel after kick, $erased users cleaned up from lists") if $main::debug;
			do_join($nid,$channel);
		}
	}
}

sub notice ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$text) = @_;
	trigger_on_notice($nid,$server,$nick,$ident,$host,$target,$text);
	lprint_directed("NOTICE",$nick,$nid,$target,$text);
}
 
sub privmsg ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$text) = @_;
	trigger_on_privmsg($nid,$server,$nick,$ident,$host,$target,$text);
	lprint_directed("PRIVMSG",$nick,$nid,$target,$text);
}

sub do_join ($$;$) {
	my ($nid,$channel,$key) = @_;
	if (defined($key)) {
		writeto($nid,"JOIN $channel $key");
	} else {
		writeto($nid,"JOIN $channel");
	}
}

sub do_part ($$;$) {
	my $nid = shift;
	my $channel = shift || "0";
	my $reason = shift || "Leaving";
	writeto($nid,"PART $channel :$reason");
}

sub join ($$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$channel) = @_;
	trigger_on_join($nid,$server,$nick,$ident,$host,$channel);
	lprint_directed("JOIN",$nick,$nid,$channel,"");
	if ((lc($nick)) eq (lc($main::netid{$nid}{nick}))) {
                writeto($nid,"MODE $channel");
                writeto($nid,"WHO $channel");
		return;
	}
	my $nref  = "$nid,$nick";
        $nicks{$nref}{lc($channel)}{has_ops} = 0;
        $nicks{$nref}{lc($channel)}{has_halfops} = 0;
        $nicks{$nref}{lc($channel)}{has_voice} = 0;
        $nicks{$nref}{lc($channel)}{has_founder} = 0;
        $nicks{$nref}{lc($channel)}{has_protect} = 0;
	if (defined $nicks{$nref}{nick}) {
		lprint("I'm seeing a person i already know, joining a channel i'm in") if $main::debug;
		if (!is_on_channel($nick,$nid,$channel)) {
			$nicks{$nref}{channels} .= "$channel ";
			lprint("Nref $nref new channel list: $nicks{$nref}{channels}") if $main::debug;
		}
	} else {
		lprint("Totally new person, adding references") if $main::debug;
                $nicks{$nref}{channels} .= "$channel ";
                $nicks{$nref}{nick} = $nick;
                $nicks{$nref}{network} = $nid;
		$nicks{$nref}{host} = $host;
		$nicks{$nref}{ident} = $ident;
		trigger_on_add_record($nid,$nick,$channel);
	}
	# if the user is logged in, update their flags as they join new channels
	# to make sure they keep status
	if (defined $nicks{$nref}{login}) {
                $nicks{$nref}{lc($channel)}{flags}  = $main::users{$nicks{$nref}{login}}{FLAGS}{$nid}{lc($channel)};
                $nicks{$nref}{lc($channel)}{flags} .= $main::users{$nicks{$nref}{login}}{FLAGS}{_}{_};
                $nicks{$nref}{lc($channel)}{flags} .= $main::users{$nicks{$nref}{login}}{FLAGS}{_}{lc($channel)};
                $nicks{$nref}{lc($channel)}{flags} .= $main::users{$nicks{$nref}{login}}{FLAGS}{$nid}{_};
                $nicks{$nref}{lc($channel)}{flags}  = trim($nicks{$nref}{lc($channel)}{flags});
                lprint("Copy flags: '$nicks{$nref}{lc($channel)}{flags}' to $nref ($nicks{$nref}{login}) on channel '$channel'") if $main::debug;
	}
}

sub nick  ($$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$newnick) = @_;
	trigger_on_nick($nid,$server,$nick,$ident,$host,$newnick);
	lprint_directed("NICK",$nick,$nid,$newnick,"");
	my $nref  = "$nid,$nick";
	my $newnref = "$nid,$newnick";
        $nicks{$nref}{host} = $host;
        $nicks{$nref}{ident} = $ident;
	$nicks{$newnref} = $nicks{$nref};
	$nicks{$newnref}{nick} = $newnick;
	delete $nicks{$nref};
	lprint("Nickchange test: channels for $newnick are still '$nicks{$newnref}{channels}'") if $main::debug;
}

sub part ($$$$$$;$$) {
	my ($nid,$server,$nick,$ident,$host,$channel,$reason,$triggerparts) = @_;
	if ($triggerparts != 1) {
		trigger_on_part($nid,$server,$nick,$ident,$host,$channel,$reason);
		lprint_directed("PART",$nick,$nid,$channel,$reason);
	}
	my $nref  = "$nid,$nick";
	lprint("Nref $nref is parting $channel") if $main::debug;
	# clear these for security
        $nicks{$nref}{lc($channel)}{has_ops} = 0;
        $nicks{$nref}{lc($channel)}{has_halfops} = 0;
        $nicks{$nref}{lc($channel)}{has_voice} = 0;
        $nicks{$nref}{lc($channel)}{has_founder} = 0;
        $nicks{$nref}{lc($channel)}{has_protect} = 0;
	my @chanlist = $nicks{$nref}{channels};
	lprint("Old channel list: $nicks{$nref}{channels}") if $main::debug;
	$nicks{$nref}{channels} =~ s/\Q$channel\E\s//i;
	$nicks{$nref}{channels} = trim($nicks{$nref}{channels}) . " ";
	lprint("Users new channel list: $nicks{$nref}{channels}") if $main::debug;
	if (trim($nicks{$nref}{channels}) eq "") {
		lprint("This user has left all channels, nuke it") if $main::debug;
		trigger_on_del_record($nid,$nick,$channel);
		delete $nicks{$nref};
	}
}

sub quit ($$$$$;$) {
	my ($nid,$server,$nick,$ident,$host,$reason) = @_;
	trigger_on_quit($nid,$server,$nick,$ident,$host,$reason);
	lprint_directed("QUIT",$nick,$nid,"",$reason);
	my $nref  = "$nid,$nick";
	trigger_on_del_record($nid,$nick,undef);
	delete $nicks{$nref};
}

sub im_banned($$$$$$$@) {
	my ($nid,$server,undef,undef,undef,undef,$channel,$text) = @_;
	lprint("Banned on $channel, setting timer for retry in 60 secs") if $main::debug;
	$banned_from{"$nid,$channel"} = 1;
	main::create_timer("_rejoin_timer","main","rejoin_timer",60);
}

sub rejoin_timer
{
	main::delete_timer("_rejoin_timer");
	foreach my $netchannel (keys %banned_from)
	{
		my ($nid,$channel) = split(',',$netchannel,2);
		lprint("Attempt to rejoin $channel on $nid (was banned)") if $main::debug;
		do_join($nid, $channel);
	}
	%banned_from = ();
}

sub handle_names_list ($$$$$$$@) {
	my ($nid,$server,undef,undef,undef,undef,undef,$channel,$nameslist) = @_;
	lprint("Parse names list for $channel") if $main::debug;
	foreach my $person (split(' ',$nameslist)) {
		my $pers = $person;
		$pers =~ s/^[\&\~\@\+\%]//;
		my $nref  = "$nid,$pers";
		$nicks{$nref}{lc($channel)}{has_ops} = 0;
		$nicks{$nref}{lc($channel)}{has_halfops} = 0;
		$nicks{$nref}{lc($channel)}{has_voice} = 0;
		$nicks{$nref}{lc($channel)}{has_founder} = 0;
		$nicks{$nref}{lc($channel)}{has_protect} = 0;
		if ($person =~ /^\@/) {
			$nicks{$nref}{lc($channel)}{has_ops} = 1;
		} elsif ($person =~ /^\%/) {
			$nicks{$nref}{lc($channel)}{has_halfops} = 1;
		} elsif ($person =~ /^\+/) {
			$nicks{$nref}{lc($channel)}{has_voice} = 1;
		} elsif ($person =~ /^\~/) {
			$nicks{$nref}{lc($channel)}{has_founder} = 1;
		} elsif ($person =~ /^\&/) {
			$nicks{$nref}{lc($channel)}{has_protect} = 1;
		} elsif ($person =~ /^\!/) {
			$nicks{$nref}{lc($channel)}{has_founder} = 1;
		}
		$person =~ s/^[\&\~\@\+\%]//;
		$nicks{$nref}{channels} .= "$channel ";
		$nicks{$nref}{nick} = $person;
		$nicks{$nref}{network} = $nid;
		trigger_on_add_record($nid,$person,$channel);
	}
}

sub add_command ($$) {
	my ($command,$sub) = @_;
	if (!defined $botcmdtable{"$command"}) {
		$botcmdtable{"$command"} = $sub;
	}
}

sub del_command ($) {
	my ($command) = @_;
	delete $botcmdtable{"$command"};
}

sub do_command ($$$$$@) {
	my ($nid,$nick,$ident,$host,$command,@params) = @_;
	$command = uc($command);
	if (($command =~ /^init-$main::masterkey$/i) && ($main::masterkey != 0)) {
		return handle_userfile_init($nid,$nick,$ident,$host,CORE::join(' ',@params));
        } elsif (defined $botcmdtable{"$command"}) {
                return $botcmdtable{"$command"}($nid,$nick,$ident,$host,@params);
        } else {
		my @lines = trigger_on_command($nid,$nick,$ident,$host,$command,@params);
		lprint("Lines 0 = $lines[0]");
		return @lines;
        }
	return ();
}

sub handle_config {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!hasflag($nicks{$nref}{login},"owner")) {
                return ("You must be an owner to use this command");
	} else {
		my $action = shift @params;
		if ($action =~ /^dump$/i) {
			return ("\002Configuration data dump\002",split('\n',Dumper(%main::config)));
		} elsif ($action =~ /^set$/i) {
			my $network = shift @params;
			my $var = shift @params;
			my $value = join(' ',@params);
			if ((!defined $network) || (!defined $var) || (!defined $value)) {
				return ("Required parameter missing");
			}
			$main::config{$network}{$var} = $value;
			return ("Set \$main::config{$network}{$var} \002=>\002 $value");
		} elsif ($action =~ /^del$/i) {
			my $key = shift @params;
			if (!defined $key) {
				return ("No root key specified");
			}
			my $var = shift @params;
			if (!defined $var) {
				delete $main::config{$key};
				return ("Deleted \$main::config{$key}","\002WARNING:\002 Removing entire keys at runtime is \002DANGEROUS\002! things might go a bit weird...");
 			} else {
				delete $main::config{$key}{$var};
				return ("Deleted \$main::config{$key}{$var}");
			}
		}
		return ("Invalid CONFIG parameter");
	}
}

# config   = {

sub handle_addop {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if ((!hasflag($nicks{$nref}{login},"owner")) && (!hasflag($nicks{$nref}{login},"master"))) {
                return ("You must be an owner or master to use this command");
        } else {
                my ($handle,$channel) = @params;
                if (case_find_handle($handle) ne "") {
                        return ("User \002$handle\002 already exists!");
                }
		my $oldhandle = $handle;
		$handle = case_find_nick($handle,$nid);
		if ($handle eq "") {
			return ("User \002$oldhandle\002 is not on $nid.");
		}
		my $nref2 = "$nid,$handle";
                my $translate_host = $nicks{$nref2}{host};
                $translate_host =~ s/\./\\\./g;
                $translate_host = "$translate_host\$";
                my $randompass = generate_random_string(8);
                lprint("$nicks{$nref}{login} adding user $handle ($channel Operator)");
                $main::users{$handle}{DESC} = "$channel Operator";
		$main::users{$handle}{FLAGS}{$nid}{lc($channel)} = "operator ";
		$main::users{$handle}{PASS} = passwordhash($randompass);
		$main::users{$handle}{HOST} = "$translate_host ";
                &saveuserfile($main::userfile);
                return ("Added user \002$handle\002 as an operator of \002$channel\002, password is '\002$randompass\002'");
        }
        return ();
}

sub handle_addmaster {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!hasflag($nicks{$nref}{login},"owner")) {
                return ("You must be an owner to use this command");
        } else {
                my ($handle,$channel) = @params;
                if (case_find_handle($handle) ne "") {
                        return ("User \002$handle\002 already exists!");
                }
                my $oldhandle = $handle;
                $handle = case_find_nick($handle,$nid);
                if ($handle eq "") {
                        return ("User \002$oldhandle\002 is not on $nid.");
                }
                my $nref2 = "$nid,$handle";
                my $translate_host = $nicks{$nref2}{host};
                $translate_host =~ s/\./\\\./g;
                $translate_host = "$translate_host\$";
                my $randompass = generate_random_string(8);
                lprint("$nicks{$nref}{login} adding user $handle ($channel Master)");
                $main::users{$handle}{DESC} = "$channel Master";
                $main::users{$handle}{FLAGS}{$nid}{lc($channel)} = "master ";
                $main::users{$handle}{PASS} = passwordhash($randompass);
                $main::users{$handle}{HOST} = "$translate_host ";
                &saveuserfile($main::userfile);
                return ("Added user \002$handle\002 as an master of \002$channel\002, password is '\002$randompass\002'");
        }
        return ();
}


sub handle_adduser {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $params = CORE::join(' ',@params);
	my $nref = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	if ((!hasflag($nicks{$nref}{login},"owner")) && (!hasflag($nicks{$nref}{login},"master"))) {
		return ("You must be an owner or master to use this command");
	} else {
		my ($handle,$desc) = split(' ',$params,2);
	        if (case_find_handle($handle) ne "") {
			return ("User \002$handle\002 already exists!");
	        }
		lprint("$nicks{$nref}{login} adding user $handle ($desc)");
		$main::users{$handle}{DESC} = $desc;
		&saveuserfile($main::userfile);
		return ("Added user \002$handle\002 with the description \002$desc\002.","Before this user can login, you should add hosts and set a password.");
	}
	return ();
}

sub case_find_handle ($) {
	my ($handle) = @_;
	if (!defined $main::users{$handle}) {
		foreach my $name (keys %main::users) {
			if (lc($handle) eq lc($name)) {
				return $name;
			}
		}
		return "";
	}
	return $handle;
}

sub case_find_nick ($$) {
        my ($handle,$network) = @_;
	my $nref = "$network,$handle";
        if (!defined $nicks{$nref}) {
                foreach my $name (keys %nicks) {
			my ($a,$b) = split(',',$name);
                        if (lc($b) eq lc($handle)) {
                                return $b;
                        }
                }
                return "";
        }
        return $handle;
}


sub handle_addflags {
	# ADDFLAGS <handle> <network> <#channel> <flags>
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        my ($handle,$flagnet,$flagchan,@flags) = @params;
	my $flags = CORE::join(' ',@flags);
	my $oflagnet = $flagnet;
	my $oflagchan = $flagchan;
        my $oldhandle = $handle;
        $handle = case_find_handle($handle);
        if ($handle eq "") {
                return ("User \002$oldhandle\002 does not exist!");
        }
        if (!canchange($nicks{$nref}{login},$handle)) {
                return ("You cannot change the settings of users with higher flags than you.");
        }
        if (!is_master_or_owner_on($nicks{$nref}{login},$flagchan)) {
                return ("Insufficient privilages!");
        }
	if ($flagnet eq "*") { $flagnet = "_" };
	if ($flagchan eq "*") { $flagchan = "_" };
	# now save the old list
	my $oldflaglist = $main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)};
	# temporarily promote them...
	$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)} .= "$flags ";
	# ...and check that the user hasnt made someone more powerful than themselves
        if (!canchange($nicks{$nref}{login},$handle)) {
		# if they have, put it back, and slap their wrists
		$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)} = $oldflaglist;
		return ("Naughty! You cannot modify a user to be more powerful than yourself! Do not pass go, do not collect \$100.");
        }
	if (!is_master_or_owner_on($nicks{$nref}{login},$flagchan)) {
		$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)} = $oldflaglist;
		return ("Insufficient privilages!");
	}
	saveuserfile($main::userfile);
	return ("Added flags '\002$flags\002' to user \002$handle\002.");
}

sub flagin ($$) {
	my ($check,$list) = @_;
	my @list = split(' ',trim($list));
	foreach my $x (@list) {
		if ($x eq $check) {
			return 1;
		}
	}
	return 0;
}

sub is_master_or_owner_on ($$) {
	my ($handle,$flagchan) = @_;
	my $buildlist = $main::users{$handle}{FLAGS}{_}{lc($flagchan)} . $main::users{$handle}{FLAGS}{_}{_};
        foreach my $nid (keys %main::config) {
		my $buildlist .= $main::users{$handle}{FLAGS}{$nid}{lc($flagchan)};
        }
	return (flagin("master",$buildlist) || flagin("owner",$buildlist));

}

sub handle_delflags {
        # DELFLAGS <handle> <network> <#channel> <flags>
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        my ($handle,$flagnet,$flagchan,@flags) = @params;
        my $flags = CORE::join(' ',@flags);
        my $oflagnet = $flagnet;
        my $oflagchan = $flagchan;
        my $oldhandle = $handle;
        $handle = case_find_handle($handle);
        if ($handle eq "") {
                return ("User \002$oldhandle\002 does not exist!");
        }
        if (!canchange($nicks{$nref}{login},$handle)) {
                return ("You cannot change the settings of users with higher flags than you.");
        }
        if (!is_master_or_owner_on($nicks{$nref}{login},$flagchan)) {
                return ("Insufficient privilages!");
        }
        if ($flagnet eq "*") { $flagnet = "_" };
        if ($flagchan eq "*") { $flagchan = "_" };
	my $newflags = "";
	my $gotone = 0;
	foreach my $cflag (split(' ',$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)})) {
		if (flagin($cflag,$flags)) {
			$gotone = 1;
		} else {
			$newflags .= "$cflag ";
		}
	}
	if ($gotone) {
               	$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)} = "$newflags ";
		if (trim($main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)}) eq "") {
			$main::users{$handle}{FLAGS}{$flagnet}{lc($flagchan)} = undef;
		}
		saveuserfile($main::userfile);
		$newflags = trim($newflags);
		return ("Removed flags '\002$flags\002' from user \002$handle\002. Users flags on $oflagnet,$oflagchan are now '\002$newflags\002'");
	} else {
		return ("User \002$handle\002 does not have any of the flags in the set '\002$flags\002' on $oflagnet,$oflagchan!");
	}
}

sub handle_chpass {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	my ($handle,$pass) = @params;
	my $oldhandle = $handle;
	$handle = case_find_handle($handle);
	if ($handle eq "") {
		return ("User \002$oldhandle\002 does not exist!");
	}
        if (!canchange($nicks{$nref}{login},$handle)) {
                return ("You cannot change the settings of users with higher flags than you.");
        }
	lprint("$nicks{$nref}{login} changed password for $handle");
	$main::users{$handle}{PASS} = passwordhash($pass);
	saveuserfile($main::userfile);
	return ("Password for user \002$handle\002 changed.");
}

sub handle_quit {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!hasflag($nicks{$nref}{login},"owner")) {
                return ("You must be an owner to use this command");
        } else {
		saveuserfile($main::userfile);
		exit(0);
	}
}

sub do_timestamp () {
        my ($sec, $min, $hour, $mday, $mon, $year, undef, undef, undef) = localtime(time);
        return sprintf("%4d-%02d-%02d %02d:%02d:%02d ",$year+1900,$mon+1,$mday,$hour,$min,$sec);
}

sub get_uptime {
	my $secs = time() - $main::LOADTIME;
	my $mins = $secs / 60;
	my $hours = 0;
	my $days = 0;
	$secs = $secs % 60;
	if ($mins > 59) {
		$hours = $mins / 60;
		$mins = $mins % 60;
		if ($hours > 23) {
			$days = $hours / 24;
			$hours = $hours % 24;
		}
	}
	$days = floor($days);
	$hours = floor($hours);
	$mins = floor($mins);
	$secs = floor($secs);
	return ($days, $hours, $mins, $secs);
}

sub handle_uptime {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	my ($days, $hours, $mins, $secs) = main::get_uptime();
	return ("Bot uptime: $days days, $hours hours, $mins mins, $secs secs.");
}

sub handle_deluser {
	my ($nid,$nick,$ident,$host,$handle) = @_;
	my $nref = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	my $oldhandle = $handle;
	$handle = case_find_handle($handle);
	if ($handle eq "") {
		return ("User \002$oldhandle\002 does not exist!");
	}
	if (!canchange($nicks{$nref}{login},$handle)) {
		return ("You cannot change the settings of users with higher flags than you.");
	}
	if ($nicks{$nref}{login} eq $handle) {
		return ("You fool! You cannot delete yourself!");
	}
	lprint("$nicks{$nref}{login} deleted user $handle");
	delete $main::users{$handle};
	saveuserfile($main::userfile);
	return ("User \002$handle\002 deleted.");
}

sub canchange ($$) {
	my ($source,$dest) = @_;
	# if they arent an owner OR a master, they cant change anything
	if ((!hasflag($source,"master")) && (!hasflag($source,"owner"))) {
		return 0;
	}
	# if they are a master but the other is an owner,and they arent,
	# they cant change anything either
	if ((hasflag($source,"master")) && (!hasflag($source,"owner"))) {
		if (hasflag($dest,"owner")) {
			return 0;
		}
	}
	# theyre both master.
	# do they both have master on a common channel? If not, they cant
	# do anything to each other.
	if ((hasflag($source,"master")) && (hasflag($dest,"master"))) {
		my $ok = 0;
		foreach my $channelname (split(' ',$main::config{_}{channels})) {
			if (hasflag($source,"master","_",$channelname)) {
				$ok = 1;
			}
		}
		foreach my $nid (keys %main::config) {
			foreach my $channelname (split(' ',$main::config{$nid}{channels})) {
				if (hasflag($source,"master",$nid,$channelname)) {
					$ok = 1;
				}
			}
		}
		if (!$ok) {
			return 0;
		}
	}
	# all checks checked out :-) theyre ok
	return 1;
}

sub handle_addhost {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
        if (!defined $nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        my ($handle,$newhost) = @params;
        my $oldhandle = $handle;
        $handle = case_find_handle($handle);
        if ($handle eq "") {
                 return ("User \002$oldhandle\002 does not exist!");
        }
        if (!canchange($nicks{$nref}{login},$handle)) {
                return ("You cannot change the settings of users with higher flags than you.");
        }
        lprint("$nicks{$nref}{login} added host $newhost for $handle");
        $main::users{$handle}{HOST} .= "$newhost ";
        saveuserfile($main::userfile);
        return ("Host \002$newhost\002 added to user \002$handle\002.");
}

sub handle_delhost {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	my ($handle,$newhost) = @params;
	my $oldhandle = $handle;
	$handle = case_find_handle($handle);
	if ($handle eq "") {
		return ("User \002$oldhandle\002 does not exist!");
	}
        if (!canchange($nicks{$nref}{login},$handle)) {
                return ("You cannot change the settings of users with higher flags than you.");
        }
	lprint("$nicks{$nref}{login} deleted host $newhost from $handle");
	my $newhostlist = "";
	my $gotone = 0;
	my @hosts = split(' ',trim($main::users{$handle}{HOST}));
	foreach my $lhost (@hosts) {
		if (lc($lhost) ne lc($newhost)) {
			$newhostlist .= "$lhost ";
		} else {
			$gotone = 1;
		}
	}
	$main::users{$handle}{HOST} = $newhostlist;
	if ($gotone) {
		saveuserfile($main::userfile);
		return ("Deleted host \002$newhost\002 from user \002$handle\002");
	} else {
		return ("User \002$handle\002 does not have the host \002$newhost\002");
	}
}

sub handle_modules {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
	my @return = ();
	if (defined $nicks{$nref}{login}) {
		my $header = "\002" . sprintf("%-30s","FILE") . sprintf("%-30s","NAMESPACE") . "\002";
		push @return, $header;
		for(1 .. scalar(@main::modules)) {
			push @return,  sprintf("%-30s",$main::modfiles[$_]) .  sprintf("%-30s",$main::modules[$_]);
		}
		return @return;
	} else {
		return ("You are not logged in!");
	}
}

sub handle_networks {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $nref = "$nid,$nick";
        my @return = ();
        if (defined $nicks{$nref}{login}) {
                my $header = "\002" . sprintf("%-15s","NAME") . sprintf("%-30s","ADDRESS") .sprintf("%-30s","IP") .sprintf("%-4s","UP") .sprintf("%-6s","BUFSZ") .sprintf("%-4s","SSL").sprintf("%-5s","LAG")."\002";
                push @return, $header;
                foreach my $key (keys %main::netid) {
                        push @return,  sprintf("%-15s",$key) . sprintf("%-30s",$main::netid{$key}{server}) . sprintf("%-30s",$main::netid{$key}{ip}) . sprintf("%-4s",(!defined($main::reconnect{$key})) ? "yes" : "no")." ".sprintf("%-5d",length($main::buffers{$key})).sprintf("%-4s",$main::netid{$key}{ssl} ? "yes" : "no").sprintf("%-5d",$main::netid{$nid}{lag});
                }
                return @return;
	} else {
		return ("You are not logged in!");
	}
}

sub handle_match {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my @return = ();
	my $nref = "$nid,$nick";
	if (defined $nicks{$nref}{login}) {
		foreach my $handle (keys %main::users) {
			eval {
				if ($handle =~ /$params[0]/i) {
					push @return, "\002Nickname:    \002" . $handle;
					push @return, "\002Password:    \002" . (defined $main::users{$handle}{PASS} ? "set" : "not set");
					push @return, "\002Description: \002" . $main::users{$handle}{DESC};
					push @return, "\002Hosts:\002";
					foreach my $host (split(' ',$main::users{$handle}{HOST})) {
						push @return, sprintf("%-45s", $host);
					}
					push @return, "\002Flags:\002";
					push @return, "\002".sprintf("%-15s", "Network").sprintf("%-15s", "Channel")."   Flags\002";
					foreach my $channelname (split(' ',$main::config{_}{channels})) {
						push @return, sprintf("%-15s", "*").sprintf("%-15s", $channelname)."   ".$main::users{$handle}{FLAGS}{_}{lc($channelname)} if (defined $main::users{$handle}{FLAGS}{_}{lc($channelname)});
					}
					foreach my $nid (keys %main::config) {
						push @return, (sprintf("%-15s", ($nid eq "_" ? "*" : $nid)).sprintf("%-15s", "*")."   ".$main::users{$handle}{FLAGS}{$nid}{_}) if (defined $main::users{$handle}{FLAGS}{$nid}{_});
					}
		                        foreach my $nid (keys %main::config) {
		                                my @chans = split(' ',$main::config{$nid}{channels});
		                                if ($nid eq "_") { @chans = () };
		                                foreach my $channelname (@chans) {
		                                        push @return, sprintf("%-15s", $nid).sprintf("%-15s", ($channelname eq "_" ? "*" : $channelname))."   ".$main::users{$handle}{FLAGS}{$nid}{lc($channelname)} if (defined $main::users{$handle}{FLAGS}{$nid}{lc($channelname)});
		                                }
		                        }
					push @return, " ";
				}
			}
		}
		return @return;
	} else {
		return ("You are not logged in!");
	}
}

sub handle_pass {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $params = CORE::join(' ',@params);
	my @plist = split(' ',$params);
	my ($old,$new) = @plist;
	my $nref = "$nid,$nick";
	if (scalar(@plist) == 1) {
		# one parameter version, must be logged in to use this
		if (defined $nicks{$nref}{login}) {
			$main::users{$nicks{$nref}{login}}{PASS} = passwordhash($old);
			saveuserfile($main::userfile);
			return ("Password changed.");
		} else {
			return ("You are not logged in. You must log in to use PASS with one parameter.");
		}
	} else {
		# two parameter version, can be logged in or out to use this one
		my $found_nick = matcheshost($ident,$host);
		if (!comparepassword($found_nick,$old)) {
			$main::users{$found_nick}{PASS} = passwordhash($new);
			saveuserfile($main::userfile);
			return ("Password changed.");
		} else {
			return ("Old password is incorrect.");
		}
	}
}


sub generate_random_string ($) {
	my $length_of_randomstring = (shift || 8);
	my @chars = ('a'..'z','A'..'Z');
	my $random_string = "";
	foreach (1 .. $length_of_randomstring) {
		$random_string .= $chars[rand @chars];
	}
	return $random_string;
}



sub handle_userfile_init {
	my ($nid,$nick,$ident,$host,$params) = @_;
	my @ret = ();
	push @ret, ("Welcome to botnix, $nick! I am setting you as the owner of this bot.", "Creating default userfile...");
	my $fail = 0;
	open(UF,">$main::userfile") or $fail = 1;
	if (!$fail) {
		my $translate_host = $host;
		my $translate_ident = $ident;
		$translate_host =~ s/\./\\\./g;
		$translate_ident =~ s/\./\\\./g;
		$translate_host = "$translate_ident\\\@$translate_host\$";
		my $randompass = generate_random_string(8);
		print UF "$nick HOST $translate_host\n";
		print UF "$nick FLAG _ _ owner\n";
		print UF "$nick DESC Default botnix owner\n";
		print UF "$nick PASS ".passwordhash($randompass)."\n";
		close UF;
		push @ret, "Your user account has been created.";
		push @ret, "Handle:       $nick";
		push @ret, "Password:     $randompass";
		push @ret, "Host regexp:  $translate_host";
		push @ret, "You are now an owner on this bot.";
		$main::masterkey = 0;
		&loaduserfile($main::userfile);
	} else {
		push @ret, "Failed to create userfile '$main::userfile'.";
		push @ret, "Please check the directory permissions.";
	}
	return @ret;
}

sub handle_login {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $params = CORE::join(' ',@params);
	my $found_nick = matcheshost($ident,$host);
	if ($found_nick eq "") {
		return ("But... I dont know who you are!");
	}
	if (!comparepassword($found_nick,$params)) {
		return ("That password doesn't seem quite right.");
	}
	my $nref  = "$nid,$nick";
	if (defined $nicks{$nref}{login}) {
		return("You are already logged in as $nicks{$nref}{login}.");
	}
	else {
		$nicks{$nref}{login} = $found_nick;
		my @clist = get_chanlist($nid,$nick);
		foreach my $channel (@clist) {
			$nicks{$nref}{lc($channel)}{flags}  = $main::users{$found_nick}{FLAGS}{$nid}{lc($channel)};
			$nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{_}{_};
			$nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{_}{lc($channel)};
			$nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{$nid}{_};
			$nicks{$nref}{lc($channel)}{flags}  = trim($nicks{$nref}{lc($channel)}{flags});
			lprint("Copy flags: '$nicks{$nref}{lc($channel)}{flags}' to $nref ($found_nick) on channel '$channel'") if $main::debug;
		}
		return ("Hi, \002$found_nick\002, pleased to meet you.");
	}
}

sub handle_logout {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $params = CORE::join(' ',@params);
	my $nref  = "$nid,$nick";
	if (!defined $nicks{$nref}{login}) {
		return ("You are not logged in, \002$nick\002.");
	} else {
		my $found_nick = $nicks{$nref}{login};
		$nicks{$nref}{login} = undef;
		my @clist = get_chanlist($nid,$nick);
		foreach my $channel (@clist) {
			$nicks{$nref}{lc($channel)}{flags} = undef;
		}
		return ("Goodbye, \002$found_nick\002!");
	}
}

sub handle_help {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $params = CORE::join(' ',@params);
	my $nref  = "$nid,$nick";
	return build_help_text($nid,$nick,$ident,$host,$params,$nicks{$nref}{login});
}

sub wildcard_to_regexp ($) {
	my ($mask) = @_;
	$mask = quotemeta $mask;
	$mask =~ s/\\\*/[\x01-\xFF]{0,}/g;
	$mask =~ s/\\\?/[\x01-\xFF]{1,1}/g;
	return $mask;
}

1;
