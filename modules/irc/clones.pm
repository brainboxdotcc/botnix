# Please include this text with any bug reports
# $Id: clones.pm 1917 2005-10-06 21:23:02Z brain $
# =============================================

package modules::irc::clones;

my %hostcount = ();
my %action = ();
my %message = ();
my %thr = ();
my %exceptions = ();

sub init {
	my ($self) = @_;
}

sub implements {
        my @functions = ("before_configure","on_configure","on_add_record","on_del_record","on_set_record");
        return @functions;
}

sub shutdown {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
}


sub on_add_record {
	my ($self,$network,$nick,$channel) = @_;
	my $host = $main::nicks{"$network,$nick"}{host};
	if ($host ne "") {
		$hostcount{"$network,$host"}++;
		if ($hostcount{"$network,$host"} >= threshold($network,$channel)) {
			do_action($network,$channel,$hostcount{"$network,$host"},$host,$nick);
		}
	}
}

sub on_set_record {
        my ($self,$network,$nick,$channel) = @_;
        my $host = $main::nicks{"$network,$nick"}{host};
        if ($host ne "") {
                $hostcount{"$network,$host"}++;
                if ($hostcount{"$network,$host"} >= threshold($network,$channel)) {
                        do_action($network,$channel,$hostcount{"$network,$host"},$host,$nick);
                }
        }
}

sub on_del_record {
	my ($self,$network,$nick,$channel) = @_;
	my $host = $main::nicks{"$network,$nick"}{host};
	delete $hostcount{"$network,$host"};
}

sub threshold {
	my ($network,$channel) = @_;
	if (defined $thr{$network}{$channel}) {
		return $thr{$network}{$channel};
	} elsif (defined $thr{_}{$channel}) {
		return $thr{_}{$channel};
	} else {
		return 99999;
	}
}

sub do_action {
	my ($nid,$channel,$count,$host,$nick) = @_;
	my $msg = (defined $message{"$nid,$channel"} ? $message{"$nid,$channel"} : (defined $message{"_,$channel"} ? $message{"_,$channel"} : "Cloning (<num> clones, maximum is <max>)"));
	my $secs = 0;
	my $max = threshold($nid,$channel);
	$msg =~ s/<num>/$count/gi;
	$msg =~ s/<max>/$max/gi;

	foreach my $ex (%exceptions) {
		$ex = main::wildcard_to_regexp($ex);
		if ($host =~ /$ex/i) {
			return;
		}
	}

	my $action = (defined $action{"$nid,$channel"} ? $action{"$nid,$channel"} : (defined $action{"_,$channel"} ? $action{"_,$channel"} : "kickban"));
	if ($action eq "kick") {
		main::writeto($nid,"KICK $channel $nick :$msg");
	} elsif ($action eq "kickban") {
		main::add_mode_queue($nid,$channel,"+b","*!*@".$host);
		main::writeto($nid,"KICK $channel $nick :$msg");
	} elsif ($action eq "ban") {
		main::add_mode_queue($nid,$channel,"+b","*!*@".$host);
	} elsif ($action eq "deop") {
		main::add_mode_queue($nid,$channel,"-o",$nick);
	} elsif ($action eq "devoice") {
		main::add_mode_queue($nid,$channel,"-v",$nick);
	} elsif ($action eq "quiet") {
		main::add_mode_queue($nid,$channel,"+b","~q:*!*@".$host);
	}
}


sub before_configure {
        my ($self,$confname) = @_;
	%action = ();
	%message = ();
	%thr = ();
	%hostcount = ();
}

sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
	# clones "3"
	# cloneaction "kickban"
	# clonereason "clones (<num> clones, <max> allowed)"
        if ($configline =~ /^clones\s+"(.+?)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("clone command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$chan_context = lc($chan_context);
                $thr{$net_context}{$chan_context} = "$1";
        } elsif ($configline =~ /^clonereason\s+"(.+?)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("clonereason command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$message{"$net_context,$chan_context"} = "$1";
	} elsif ($configline =~ /^cloneaction\s+"(.+)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("cloneaction command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$action{"$net_context,$chan_context"} = "$1";
        } elsif ($configline =~ /^cloneexception\s+"(.+)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("cloneexception command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
                $exceptions{$1}++;
        }
	return 1;
}


1;
