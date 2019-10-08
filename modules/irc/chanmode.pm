# Please include this text with any bug reports
# $Id: chanmode.pm 1898 2005-10-01 16:09:29Z brain $
# =============================================

package modules::irc::chanmode;

my %keys = ();
my %tried = ();
my $self = "";

sub init {
	my ($me) = @_;
	my $self = $me;

	# add our help sections to the help system
	main::add_help_commands("Channel Commands",("MODE","INVITE","SETKEY","CYCLE","KEYS"));
	main::add_context_help("MODE","Syntax: MODE [network] <#channel> <modes/params>\nIssue a MODE command for the given channel."); 
	main::add_context_help("INVITE","Syntax: INVITE [network] <#channel>\nInvite a user to a channel.");
        main::add_context_help("SETKEY","Syntax: SETKEY [network] <#channel> <key>\nSets the key to be used for joining a channel");
	main::add_context_help("CYCLE","Syntax: CYCLE [network] <#channel>\nCycle (hop) the specified channel.");
	main::add_context_help("KEYS","Syntax: KEYS\nList all channel keys stored by the bot and their state.");

        # re-read all our persistent data from the backing store
        %keys = main::get_all_items($self);

	main::add_command("MODE",$self."::handle_mode");
	main::add_command("INVITE",$self."::handle_invite");
	main::add_command("SETKEY",$self."::handle_setkey");
	main::add_command("CYCLE",$self."::handle_cycle");
	main::add_command("KEYS",$self."::handle_keys");
}

sub implements {
        my @functions = ("on_single_mode","on_raw","before_configure","on_configure","on_join");
        return @functions;
}

sub shutdown {
	my ($self)= @_;
	main::del_help_commands("Channel Commands",("MODE","INVITE","SETKEY","CYCLE","KEYS"));
	main::del_context_help("MODE");
	main::del_context_help("INVITE");
	main::del_context_help("SETKEY");
	main::del_context_help("CYCLE");
	main::del_context_help("KEYS");

        main::del_command("MODE");
        main::del_command("INVITE");
        main::del_command("SETKEY");
        main::del_command("CYCLE");
        main::del_command("KEYS");

}

sub before_configure {
        my ($self,$confname) = @_;
}

sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
        if ($configline =~ /^modelock\s+"(.+)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("modelock command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
                $channelflags{$net_context}{lc($chan_context)}{modelock} = $1;
        }
	return 1;
}


sub on_join {
        my ($self,$nid,$server,$nick,$ident,$host,$target)= @_;
        if ($nick eq $main::netid{$nid}{nick}) {
                if (defined $channelflags{$nid}{lc($target)}{modelock}) {
                       main::writeto($nid,"MODE $target $channelflags{$nid}{lc($target)}{modelock}");
                } elsif (defined $channelflags{_}{lc($target)}{modelock}) {
                       main::writeto($nid,"MODE $target $channelflags{$nid}{_}{modelock}");
                }
	}
}


sub on_raw {
        my ($self,$nid,$server,$nick,$ident,$host,$command,@plist) = @_;

	# Try each keyed channel ONCE.
	# If the user has given us a key, and the key hasnt worked, dont try to rejoin any more
	# until they use SETKEY again, then try again at the next 475 numeric.

	my $channel = $plist[1];

	# 475 neuron_nix #botnix-test :Cannot join channel (+k)
        if (($command eq "475") && (defined $keys{"$nid,$channel"})) {
		if (!defined $tried{"$nid,$channel"}) {
			main::lprint("A key is set for channel $channel on $nid, using it");
			main::do_join($nid,$channel,$keys{"$nid,$channel"});
		}
        }
}

# Really clever way of checking mode enforcements for modelock :-)
sub trigger_enforce {
	my ($direction,$mode,$enforced) = @_;
	my ($mlist,undef) = split(' ',$enforced,2);
	my $set = 1;
	foreach my $modeletter (split('',$mlist)) {
		if ($modeletter eq "+") {
			$set = 1;
		} elsif ($modeletter eq "-") {
			$set = 0;
		# if direction isnt the same as set, the mode is going the opposite
		# direction to the enforcement, e.g. +i instead of -i. modeletter equals
		# mode checks its actually a mode letter in the enforce set.
		} elsif (($direction != $set) && ($modeletter eq $mode)) {
			return 1;
		}
	}
	return 0;
}

sub on_single_mode {
	my ($self,$nid,$server,$nick,$ident,$host,$mode,$direction,$target,$modeparam) = @_;
	if (($direction == 1) && ($mode eq "o")) {
		if ($modeparam eq $main::netid{$nid}{nick}) {
			if (defined $channelflags{$nid}{lc($target)}{modelock}) {
				main::writeto($nid,"MODE $target $channelflags{$nid}{lc($target)}{modelock}");
			} elsif (defined $channelflags{_}{lc($target)}{modelock}) {
				main::writeto($nid,"MODE $target $channelflags{$nid}{_}{modelock}");
			}
		}
	}
	if (defined $channelflags{$nid}{lc($target)}{modelock}) {
		if (trigger_enforce($direction,$mode,$channelflags{$nid}{lc($target)}{modelock})) {
			main::writeto($nid,"MODE $target $channelflags{$nid}{lc($target)}{modelock}");
		}
	} elsif (defined $channelflags{_}{lc($target)}{modelock}) {
		if (trigger_enforce($direction,$mode,$channelflags{_}{lc($target)}{modelock})) {
			main::writeto($nid,"MODE $target $channelflags{$nid}{_}{modelock}");
		}
	}
	if (($direction == 1) && ($mode eq "k")) {
		if ((defined $modeparam) && ($modeparam ne "")) {
	                $keys{"$nid,$target"} = $modeparam;
	                delete $tried{"$nid,$target"};
	                main::store_item($self,"$nid,$target",$modeparam);
		}
	}
}

sub handle_mode {
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
	my $modes = join(' ',@params);
        main::writeto($network,"MODE $channel $modes");
        return ("Set modes \002$modes\002 on $network/$channel");
}

sub handle_invite {
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
	my $user = join(' ',@params);
        main::writeto($network,"INVITE $user $channel");
        return ("Invited user \002$user\002 to $network/$channel");
}

sub handle_setkey {
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
        my $key = join(' ',@params);
        $keys{"$network,$channel"} = $key;
	delete $tried{"$network,$channel"};
        main::store_item($self,"$network,$channel",$key);
        return ("Set the key to \002$key\002 for $network/$channel");
}

sub handle_cycle {
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
	main::do_part($network,$channel);
	# use the key if its defined
	main::do_join($network,$channel,$keys{"$network,$channel"});
        return ("Cycling channel \002$network/$channel\002 (".(defined $keys{"$network,$channel"} ? "using a key" : "not using a key").")");
}

sub handle_keys {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"owner",$network,$channel)) {
		return ("You must have owner status for this command!");
        }
        my $header = "\002".sprintf("%-10s","NETWORK").sprintf("%-15s","CHANNEL").sprintf("%-15s","KEY").sprintf("%-15s","DENIED");
        push @return, $header;
        foreach my $key (keys %keys) {
		my ($network,$channel) = split(',',$key);
                push @return, sprintf("%-10s",$network).sprintf("%-15s",$channel).sprintf("%-15s",$keys{$key}).sprintf("%-15s",(defined $tried{"$network,$channel"} ? "Yes" : "No"));
        }
        return @return;
}

1;
