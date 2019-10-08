# Please include this text with any bug reports
# $Id: chanop.pm 1908 2005-10-05 13:59:11Z brain $
# =============================================

package modules::irc::chanop;

my $self = "";
my %bans;

sub init {
	my ($me) = @_;
	my $self = $me;

	# add our help sections to the help system
	main::add_help_commands("Channel Commands",("OP","DEOP","BAN","BANLIST","KICK","KICKBAN","STICK","UNSTICK","ENFORCE","CLEARBANS"));
	main::add_context_help("OP","Syntax: OP <#channel> <nick>\n        OP <network> <#channel> <nick>\nMake the bot op a user on a channel.");
	main::add_context_help("DEOP","Syntax: DEOP <#channel> <text>\n        ACT <network> <#channel> <text>\nMake the bot deop a user on a channel.");
	main::add_context_help("BAN","Syntax: BAN ADD|DEL [network] <#channel> <mask> <reason>\nAdd or remove a ban on the given channel, setting the reason as specified.");
	main::add_context_help("BANLIST","Syntax: BANLIST\nShow a list of all active bans");
	main::add_context_help("KICK","Syntax: KICK <#channel> <nick> <reason>\n        KICK <network> <#channel> <nick> <reason>\nKicks a user from a channel with a reason.");
	main::add_context_help("KICKBAN","Syntax: KICKBAN <#channel> <nick> <reason>\n        KICKBAN <network> <#channel> <reason>\nKicks and bans a user from a channel with a reason.");
	main::add_context_help("STICK","Syntax: STICK [network] <#channel> <mask>\nStick a ban. Once stuck the bot will enforce the ban and not\nallow it to be removed.");
	main::add_context_help("UNSTICK","Syntax: UNSTICK [network] <#channel> <mask>\nUnstick a ban previously made sticky with STICK.");
	main::add_context_help("ENFORCE","Syntax: ENFORCE [network] <#channel> [sticky]\nEnforce all a channel's bans.\nIf sticky is given, enforce only sticky bans.");
	main::add_context_help("CLEARBANS","Syntax: CLEARBANS [network] <#channel>\nClear all non-sticky bans from a channel");

	main::add_command("BANLIST",$self."::handle_banlist");
	main::add_command("KICK",$self."::handle_kick");
	main::add_command("KICKBAN",$self."::handle_kickban");
	main::add_command("OP",$self."::handle_op");
	main::add_command("DEOP",$self."::handle_deop");
	main::add_command("STICK",$self."::handle_stick");
	main::add_command("UNSTICK",$self."::handle_unstick");
	main::add_command("ENFORCE",$self."::handle_enforce");
	main::add_command("BAN",$self."::handle_ban");
	 main::add_command("CLEARBANS",$self."::handle_clearbans");

	# re-read all our persistent data from the backing store
	my %sticky = main::get_all_items($self);
	foreach my $item (keys %sticky) {
		my ($banmask,$network,$channel) = split(',',$item,3);
		$channel = lc($channel);
		my ($settime,$setby,$reason) = split(' ',$sticky{$item},3);
		main::lprint("Re-read sticky ban from store: $banmask set by $setby on $network/$channel ($reason)") if $main::debug;
                $bans{"$banmask $network $channel"}{mask} = $banmask;
                $bans{"$banmask $network $channel"}{network} = $network;
                $bans{"$banmask $network $channel"}{reason} = $reason;
                $bans{"$banmask $network $channel"}{channel} = $channel;
                $bans{"$banmask $network $channel"}{settime} = $settime;
                $bans{"$banmask $network $channel"}{setby} = $setby;
                $bans{"$banmask $network $channel"}{sticky} = 1;
	}
}

sub implements {
        my @functions = ("on_join","on_raw","on_single_mode");
        return @functions;
}

sub shutdown {
	my ($self)= @_;

	main::delete_timer("chanop_stickban_timer");

	main::del_help_commands("Channel Commands",("OP","DEOP","BAN","BANLIST","KICK","KICKBAN","STICK","UNSTICK","ENFORCE","CLEARBANS"));
	main::del_context_help("OP");
	main::del_context_help("DEOP");
	main::del_context_help("BAN");
	main::del_context_help("BANLIST");
	main::del_context_help("KICK");
	main::del_context_help("KICKBAN");
	main::del_context_help("STICK");
	main::del_context_help("UNSTICK");
	main::del_context_help("ENFORCE");
	main::del_context_help("CLEARBANS");

	main::del_command("BANLIST");
        main::del_command("KICK");
        main::del_command("KICKBAN");
        main::del_command("OP");
	main::del_command("DEOP");
        main::del_command("STICK");
        main::del_command("UNSTICK");
        main::del_command("ENFORCE");
        main::del_command("BAN");
	main::del_command("CLEARBANS");
}

sub on_join {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
	$channel = lc($channel);
	if ($nick eq $main::netid{$nid}{nick}) {
		main::writeto($nid,"MODE $channel +b");
	        foreach my $item (keys %bans) {
	                if ($bans{$item}{sticky} == 1) {
				if ($bans{$item}{channel} eq $channel) {
		                        main::add_mode_queue($bans{$item}{network},$bans{$item}{channel},"+b",$bans{$item}{mask});
				}
	                }
	        }
	}
}

## How stickybans work
# The guts and gubbins.
#
# When the bot joins the channel, it tries to apply all its sticky bans. Chances are, it isnt opped. if it is,
# the bans are set, no problem.
#
# whenever the bot receives numeric 482 "you are not a channel operator" it creates a timer which runs for 120
# seconds. When the timer expires, the bot tries to set all its sticky bans again. It then deletes the timer.
# if it fails to set the bans again of course, this will result in another 482 numeric and the timer being
# created once more for another try.
#
# If someone reverses a sticky ban, then the bot re-applies it, keeping it held. However if the bot is not
# opped, then this of course causes a 482 numeric, which starts the 2 minute retry cycle all over again :-)
#
# This has the added benifit that if the bot is opered on a network that supports oper overrides, it will still
# be able to set its bans when not opped, automatically retrying, succeeding and not receiving the 481 numeric,
# as the system operates on what the server *tells it* it can do, and not what ass-u-me'd rules indicate it can
# or cant do.

sub stickyban_apply {
	foreach my $item (keys %bans) {
		if ($bans{$item}{sticky} == 1) {
			main::add_mode_queue($bans{$item}{network},$bans{$item}{channel},"+b",$bans{$item}{mask});
		}
	}
	main::delete_timer("chanop_stickban_timer");
}

sub on_raw {
	my ($self,$nid,$server,$nick,$ident,$host,$command,@plist) = @_;

	# 482 neuron_nix #botnix :You're not channel operator
	if ($command eq "482") {
		main::create_timer("chanop_stickban_timer",$self,"stickyban_apply",120);
	}

	if ($command eq "367") {
		my $channel = lc($plist[1]);
		my $network = $nid;
		my $banmask = $plist[2];
		if (!defined $bans{"$banmask $network $channel"}) {
	                $bans{"$banmask $network $channel"}{mask} = $plist[2];
	       	        $bans{"$banmask $network $channel"}{network} = $nid;
	       	        $bans{"$banmask $network $channel"}{reason} = "Set from channel join";
	       	        $bans{"$banmask $network $channel"}{channel} = lc($plist[1]);
       	        	$bans{"$banmask $network $channel"}{settime} = $plist[4];
			$bans{"$banmask $network $channel"}{setby} = $plist[3];
			$bans{"$banmask $network $channel"}{sticky} = 0;
			main::lprint("Added channel ban $plist[2] on $nid/$plist[1]") if $main::debug;
		}
	}
}

sub on_single_mode {
	my ($self,$nid,$server,$nick,$ident,$host,$mode,$direction,$target,$modeparam) = @_;
	if ($mode eq "b") {
		if ($direction == 0) {
			if ($bans{"$modeparam $nid $target"}{sticky} == 1) {
				# ban is sticky, bounce the change and dont delete it
				main::lprint("Bouncing ban $nid/$target $modeparam") if $main::debug;
				main::add_mode_queue($nid,$target,"+b",$modeparam);
			} else {
				delete $bans{"$modeparam $nid $target"};
			}
			main::lprint("Deleted channel ban $modeparam on $nid/$target") if $main::debug;
		} else {
			if (!defined $bans{"$modeparam $nid $target"}) {
				$bans{"$modeparam $nid $target"}{mask} = $modeparam;
				$bans{"$modeparam $nid $target"}{network} = $nid;
				$bans{"$modeparam $nid $target"}{reason} = "No reason";
				$bans{"$modeparam $nid $target"}{channel} = $target;
				$bans{"$modeparam $nid $target"}{settime} = time;
				$bans{"$modeparam $nid $target"}{setby} = $nick;
				$bans{"$modeparam $nid $target"}{sticky} = 0;
				main::lprint("Added channel ban $modeparam on $nid/$target") if $main::debug;
			}
		}
	}
}

sub handle_banlist {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my @return = ();
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        my $header = "\002" . sprintf("%-10s","NETWORK") . sprintf("%-15s","CHANNEL") .sprintf("%-30s","MASK") .sprintf("%-15s","SET BY") . " STK   REASON" . "\002";
        push @return, $header;
        foreach my $key (keys %bans) {
                push @return,  sprintf("%-10s",$bans{$key}{network}) .sprintf("%-15s",$bans{$key}{channel}) .sprintf("%-30s",$bans{$key}{mask}) .sprintf("%-15s",$bans{$key}{setby}) ." ".($bans{$key}{sticky} ? "Y" : "N")."    ".$bans{$key}{reason};
        }
        return @return;
}

sub handle_kick {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
		my $user = shift @params;
        my $reason = join(' ',@params);
        my $olduser = $user;
        $user = main::case_find_nick($user,$network);
        if ($user eq "") {
                return ("User \002$olduser\002 doesn't seem to be on any of my channels!");
        }
        if (!main::is_on_channel($user,$network,$channel)) {
                return ("User \002$user\002 doesn't seem to be in $channel on $network!");
        }
        main::writeto($network,"KICK $channel $user :$reason");
        return ("Kicked \002$user\002 from $network/$channel ($reason)");
}

sub handle_kickban {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
        my $user = shift @params;
        my $reason = join(' ',@params);
        my $olduser = $user;
        $user = main::case_find_nick($user,$network);
        if ($user eq "") {
                return ("User \002$olduser\002 doesn't seem to be on any of my channels!");
        }
        if (!main::is_on_channel($user,$network,$channel)) {
                return ("User \002$user\002 doesn't seem to be in $channel on $network!");
        }
		my $nref2 = "$network,$user";
		main::add_mode_queue($network,$channel,"+b","*!*@".$main::nicks{$nref2}{host});
        main::writeto($network,"KICK $channel $user :$reason");
        return ("Kickbanned \002$user\002 from $network/$channel ($reason)");
}


sub handle_op {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $target = shift @params;
	my $channel,$network;
	# just a channel
	if ($target =~ /^(\#|\&)/) {
		$channel = $target;
		$network = $nid;
	} else {
		# a channel and a network
		$network = $target;
		$channel = shift @params;
	}
	my $nref = "$nid,$nick";
	if (!defined $main::nicks{$nref}{login}) {
		return ("You are not logged in!");
	}
	if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
		return ("You do not have the operator flag on \002$network/$channel\002");
	}
	my $user = join(' ',@params);
	my $olduser = $user;
	$user = main::case_find_nick($user,$network);
	if ($user eq "") {
		return ("User \002$olduser\002 doesn't seem to be on any of my channels!");
	}
	if (!main::is_on_channel($user,$network,$channel)) {
		return ("User \002$user\002 doesn't seem to be in $channel on $network!");
	}
	if (main::has_ops($network,$user,$channel)) {
		return ("User \002$user\002 already has ops on $network/$channel.");
	}
	main::add_mode_queue($network,$channel,"+o",$user);
	return ("Opped \002$user\002 on $network/$channel");
}

sub handle_stick {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
        my $banmask = shift @params;
	if (defined $bans{"$banmask $network $channel"}) {
		$bans{"$banmask $network $channel"}{sticky} = 1;
		main::store_item($self,
				"$banmask,$network,$channel",
				$bans{"$banmask $network $channel"}{settime}." ".
				$bans{"$banmask $network $channel"}{setby}." ".
				$bans{"$banmask $network $channel"}{reason});
		return ("Stuck ban \002$banmask\002 on $network/$channel (".$bans{"$banmask $network $channel"}{reason}.")");
	} else {
		return ("Ban \002$banmask\002 does not exist on $network/$channel!");
	}
}

sub handle_unstick {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
        my $banmask = shift @params;
        if (defined $bans{"$banmask $network $channel"}) {
                $bans{"$banmask $network $channel"}{sticky} = 0;
		main::remove_item($self,"$banmask,$network,$channel");
                return ("Unstuck ban \002$banmask\002 on $network/$channel (".$bans{"$banmask $network $channel"}{reason}.")");
        } else {
                return ("Ban \002$banmask\002 does not exist on $network/$channel!");
        }
}

sub handle_enforce {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
	my @results = ();
	my $kicked = 0;
        my $sticky = shift @params;
	my @members = main::get_members($network,$channel);
        foreach my $key (keys %bans) {
		foreach my $person (@members) {
			my $nid = "$network,$person";
			if (lc($bans{$key}{channel}) eq lc($channel)) {
				my $mask = main::wildcard_to_regexp($bans{$key}{mask});
				my $set = "$main::nicks{$nid}{nick}!$main::nicks{$nid}{ident}\@$main::nicks{$nid}{host}";
				if ($set =~ /$mask/i) {
					if (($sticky =~ /^sticky$/i) && ($bans{$key}{sticky} == 1)) {
						main::writeto($network,"KICK $channel $person :Banned: $bans{$key}{reason}");
						push @results, "Kicking \002$person\002 (matches $bans{$key}{mask}: $bans{$key}{reason})";
						$kicked++;
					} elsif ($sticky !~ /^sticky$/i) {
						main::writeto($network,"KICK $channel $person :Banned: $bans{$key}{reason}");
						push @results, "Kicking \002$person\002 (matches $bans{$key}{mask}: $bans{$key}{reason})";
						$kicked++;
					}
				}
			}
		}
	}
	push @results,"\002$kicked\002 users kicked.";
	return @results;
}

sub handle_clearbans {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
	my $bans = 0;
	foreach my $key (keys %bans) {
                if ((lc($bans{$key}{channel}) eq lc($channel)) && ($bans{$key}{network} eq $network)) {
			if ($bans{$key}{channel}{sticky} != 1) {
				$bans++;
				main::add_mode_queue($network,$channel,"-b",$bans{$key}{mask});
			}
		}
	}
	$bans = ($bans > 0 ? $bans : "no");
        return ("Removed \002$bans\002 bans on \002$network/$channel\002");
}

sub handle_ban {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $subcommand = shift @params; # add or del
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
        my $banmask = shift @params;
	my $reason = join(' ',@params);
	if ($subcommand =~ /^add$/) {
                main::add_mode_queue($network,$channel,"+b",$banmask);
		$bans{"$banmask $network $channel"}{mask} = $banmask;
		$bans{"$banmask $network $channel"}{network} = $network;
		$bans{"$banmask $network $channel"}{reason} = $reason;
		$bans{"$banmask $network $channel"}{channel} = $channel;
		$bans{"$banmask $network $channel"}{settime} = time;
		$bans{"$banmask $network $channel"}{setby} = $main::nicks{$nref}{login};
                return ("Setting ban on \002$banmask\002 on $network/$channel.");
	} elsif ($subcommand =~ /^del$/) {
		main::add_mode_queue($network,$channel,"-b",$banmask);
		delete $bans{"$banmask $network $channel"};
		return ("Removing ban on \002$banmask\002 on $network/$channel.");
	} else {
		return ("Invalid subcommand - Use only \002ADD\002 or \002DEL\002.");
	}
}

sub handle_deop {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
        my $user = join(' ',@params);
        my $olduser = $user;
        $user = main::case_find_nick($user,$network);
        if ($user eq "") {
                return ("User \002$olduser\002 doesn't seem to be on any of my channels!");
        }
        if (!main::is_on_channel($user,$network,$channel)) {
                return ("User \002$user\002 doesn't seem to be in $channel on $network!");
        }
        if (!main::has_ops($network,$user,$channel)) {
                return ("User \002$user\002 is already unopped on $network/$channel.");
        }
	main::add_mode_queue($network,$channel,"-o",$user);
	return ("Deopped \002$user\002 on $network/$channel");
}

1;
