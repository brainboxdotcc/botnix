# Please include this text with any bug reports
# $Id: flood.pm 1884 2005-09-23 13:32:23Z brain $
# =============================================

package modules::irc::flood;

my %flood = ();
my %message = ();
my %action = ();

# Instead of adding fields to the user records, we use a seperate hash.
# this cuts down a lot on processing because (unlike in winbot) we only
# have to interate over people who are talking which is usually a smaller
# subset of the user list.

my %monitor = ();

sub init {
	my ($self) = @_;
	main::create_timer("flood_expire_timer",$self,"flood_expire",1);
}

sub implements {
        my @functions = ("before_configure","on_configure","on_privmsg","on_kick","on_nick","on_single_mode","on_notice");
        return @functions;
}

sub shutdown {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
	main::delete_timer("flood_expire_timer");
}

sub on_privmsg {
        my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if ($target =~ /^[\#\&]/) {
		$monitor{"$nid,$target,$nick,message"}++;
		if (defined $flood{"$nid,$target,message"}) {
			if ($monitor{"$nid,$target,$nick,message"} > $flood{"$nid,$target,message"}{threshold})  {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,message"},$flood{"$nid,$target,message"}{threshold},"message");
			}
		}
		if (defined $flood{"_,$target,message"}) {
	                if ($monitor{"$nid,$target,$nick,message"} > $flood{"_,$target,message"}{threshold})  {
	                        do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,message"},$flood{"_,$target,message"}{threshold},"message");
	                }
		}

	}
}

sub on_kick {
        my ($self,$nid,$server,$nick,$ident,$host,$target,$channel,$reason) = @_;
	if ($target =~ /^[\#\&]/) {
		$monitor{"$nid,$target,$nick,kick"}++;
		if (defined $flood{"$nid,$target,kick"}) {
	       	        if ($monitor{"$nid,$target,$nick,kick"} > $flood{"$nid,$target,kick"}{threshold}) {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,kick"},$flood{"$nid,$target,kick"}{threshold},"kick");
	                }
		}
		if (defined $flood{"_,$target,kick"}) {
			if ($monitor{"$nid,$target,$nick,kick"} > $flood{"_,$target,kick"}{threshold})  {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,kick"},$flood{"_,$target,message"}{threshold},"kick");
			}
		}
	}
}

sub on_nick {
        my ($self,$nid,$server,$nick,$ident,$host,$newnick) = @_;
	# nick changes are global, so we penalize the user on all their channels
	foreach my $thischan (main::get_chanlist($nid,$nick)) {
		if (defined $flood{"$nid,$thischan,nick"}) {
			$monitor{"$nid,$thischan,$nick,nick"}++;
	                if ($monitor{"$nid,$thischan,$nick,nick"} > $flood{"$nid,$thischan,nick"}{threshold}) {
				do_action($nid,$thischan,$nick,$monitor{"$nid,$thischan,$nick,nick"},$flood{"$nid,$thischan,nick"}{threshold},"nick");
	                }
		}
		if (defined $flood{"_,$target,nick"}) {
	                if ($monitor{"$nid,$thischan,$nick,nick"} > $flood{"_,$thischan,nick"}{threshold})  {
				do_action($nid,$thischan,$nick,$monitor{"$nid,$thischan,$nick,nick"},$flood{"_,$thischan,nick"}{threshold},"nick");
	                }
		}
	}
}

sub on_single_mode {
	my ($self,$nid,$server,$nick,$ident,$host,$mode,$direction,$target,$modeparam) = @_;
	if ($target =~ /^[\#\&]/) {
		if (defined $flood{"$nid,$target,mode"}) {
			$monitor{"$nid,$target,$nick,mode"}++;
	       	        if ($monitor{"$nid,$target,$nick,mode"} > $flood{"$nid,$target,mode"}{threshold}) {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,mode"},$flood{"$nid,$target,mode"}{threshold},"mode");
	                }
		}
		if (defined $flood{"_,$target,mode"}) {
	                if ($monitor{"$nid,$target,$nick,mode"} > $flood{"_,$target,mode"}{threshold})  {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,mode"},$flood{"_,$target,mode"}{threshold},"mode");
	                }
		}
	}
}

sub on_notice {
        my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if ($target =~ /^[\#\&]/) {
		if (defined $flood{"$nid,$target,message"}) {
			$monitor{"$nid,$target,$nick,message"}++;
	                if ($monitor{"$nid,$target,$nick,message"} > $flood{"$nid,$target,message"}{threshold}) {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,message"},$flood{"$nid,$target,message"}{threshold},"message");
	                }
		}
		if (defined $flood{"_,$target,message"}) {
			if ($monitor{"$nid,$target,$nick,message"} > $flood{"_,$target,message"}{threshold})  {
				do_action($nid,$target,$nick,$monitor{"$nid,$target,$nick,message"},$flood{"_,$target,message"}{threshold},"message");
			}
		}
	}
}

sub do_action {
	my ($nid,$channel,$nick,$peak,$threshold,$typestr) = @_;
	my $msg = (defined $message{"$typestr,$nid,$channel"} ? $message{"$typestr,$nid,$channel"} : (defined $message{"$typestr,_,$channel"} ? $message{"$typestr,_,$channel"} : "<type> flood (<num> in <secs> secs)"));
	my $secs = 0;
	if (defined $flood{"$nid,$channel,$typestr"}) {
		$secs = $flood{"$nid,$channel,$typestr"}{secs};
	} elsif (defined $flood{"_,$channel,$typestr"}) {
		$secs = $flood{"_,$channel,$typestr"}{secs};
	}
	$msg =~ s/<type>/$typestr/gi;
	$msg =~ s/<num>/$peak/gi;
	$msg =~ s/<secs>/$secs/gi;
	$msg =~ s/<thr>/$threshold/gi;
	my $action = (defined $action{"$typestr,$nid,$channel"} ? $action{"$typestr,$nid,$channel"} : (defined $action{"$typestr,_,$channel"} ? $action{"$typestr,_,$channel"} : "kick"));
	if ($action eq "kick") {
		main::writeto($nid,"KICK $channel $nick :$msg");
	} elsif ($action eq "kickban") {
		main::add_mode_queue($nid,$channel,"+b","*!*@".$main::nicks{"$nid,$nick"}{host});
		main::writeto($nid,"KICK $channel $nick :$msg");
	} elsif ($action eq "ban") {
		main::add_mode_queue($nid,$channel,"+b","*!*@".$main::nicks{"$nid,$nick"}{host});
	} elsif ($action eq "deop") {
		main::add_mode_queue($nid,$channel,"-o",$nick);
	} elsif ($action eq "devoice") {
		main::add_mode_queue($nid,$channel,"-v",$nick);
	} elsif ($action eq "quiet") {
		main::add_mode_queue($nid,$channel,"+b","~q:*!*@".$main::nicks{"$nid,$nick"}{host});
	}
}

sub flood_expire {
	my $now_time = time();
	my %mon = %monitor;
	foreach my $data (keys %flood) {
		my ($net,$chan,$type) = split(',',$data);
		if (($now_time % $flood{$data}{secs}) == 0) {
			# its time to process this item now
			foreach my $item (keys %mon) {
				my ($net2,$chan2,$nick2,$type2) = split(',',$item);
				if ($type eq $type2) {
					# clear counters of this type in all monitored users
					delete $monitor{"$item"};
				}
			}
		}
	}
}

sub before_configure {
        my ($self,$confname) = @_;
	%monitor = ();
	%flood = ();
	%message = ();
	%action = ();
}

sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
	# flood "message" "3:6"
	# flood "mode" "9:5"
	# flood "nick" "2:2"
	# flood "kick" "3:1"
	# floodreason "message" "message flood (<num> in <secs> secs!)"
	# floodaction "kick|kickban|deop|ban|devoice|quiet"
        if ($configline =~ /^flood\s+"(.+)"\s+"(.+?)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("flood command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$chan_context = lc($chan_context);
                $flood{"$net_context,$chan_context,$1"}{secs} = (split(':',$2))[1];
		$flood{"$net_context,$chan_context,$1"}{threshold} = (split(':',$2))[0];
        } elsif ($configline =~ /^floodreason\s+"(.+)"\s+"(.+?)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("floodreason command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$message{"$1,$net_context,$chan_context"} = $2;
	} elsif ($configline =~ /^floodaction\s+"(.+)"\s+"(.+)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("floodaction command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$action{"$1,$net_context,$chan_context"} = $2;
	}
	return 1;
}


1;
