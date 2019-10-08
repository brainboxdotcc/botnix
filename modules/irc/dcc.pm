# Please include this text with any bug reports
# $Id: dcc.pm 1836 2005-09-20 11:29:19Z brain $
# =============================================

package modules::irc::dcc;

$VERSION = "0.1";

my %dccs;

sub init {
	my($self) = @_;
}

sub send_dcc {
	my ($id,$text) = @_;
	$text .= "\r\n";
	main::write_socket($id,$text);
	$dccs{"dcc $nick $nid"}{out} += length($text);
}

sub socket_callback {
	my ($self,$id) = @_;
	my $result = main::read_socket($id);
	$dccs{"dcc $nick $nid"}{in} += length($result);
	if ($result eq "") {
		main::lprint("DCC Connection '$id' failed") if $main::debug;
		main::delete_socket($id);
		main::lprint("Deleted socket") if $main::debug;
		delete $dccs{$id};
		return;
	} else {
		chomp($result);
		$result =~ s/(\r|\n)//g;
		if ($result eq "") { return };
		main::lprint("DCC Data on '$id': '$result'") if $main::debug;
		if ($dccs{$id}{state} == 0) {
			# password check state
			if (!main::comparepassword($dccs{$id}{lnick},$result)) {
				send_dcc($id,"Invalid password!");
				main::delete_socket($id);
				delete $dccs{$id};
				return;
			}
			$dccs{$id}{state} = 1;
			my $nref  = "$dccs{$id}{network},$dccs{$id}{nick}";
			$main::nicks{$nref}{login} = $dccs{$id}{lnick};
	                my @clist = main::get_chanlist($nid,$nick);
	                foreach my $channel (@clist) {
	                        $main::nicks{$nref}{lc($channel)}{flags}  = $main::users{$dccs{$id}{lnick}}{FLAGS}{$nid}{lc($channel)};
	                        $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$dccs{$id}{lnick}}{FLAGS}{_}{_};
				$main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$dccs{$id}{lnick}}{FLAGS}{$nid}{_};
	                        $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$dccs{$id}{lnick}}{FLAGS}{_}{lc($channel)};
	                        $main::nicks{$nref}{lc($channel)}{flags}  = trim($main::nicks{$nref}{lc($channel)}{flags});
	                }
			send_dcc($id,"Welcome, \002$dccs{$id}{lnick}\002!");
		} else {
			# logged in state

			# starts with a dot? its a command, strip the dot.
			if ($result =~ /^\./) {
				$result =~ s/^\.//;
				handle_command($id,$result);
			}
			my $nref  = "$dccs{$id}{network},$dccs{$id}{nick}";
			if ($main::nicks{$nref}{login} eq "") {
				send_dcc($id,"Logging out, goodbye!");
				main::delete_socket($id);
				delete $dccs{$id};
				return;
			}
		}
	}
}

sub handle_command {
	my ($id,$text) = @_;
	my @params = split(' ',$text);
	my $command = shift @params;
	main::lprint("handle command $command in dcc") if $main::debug;
	my @return = main::do_command($dccs{$id}{network},$dccs{$id}{nick},$dccs{$id}{ident},$dccs{$id}{host},$command,@params);
	foreach my $line (@return) {
		send_dcc($id,$line);
	}
}

sub implements {
        my @functions = ("before_configure","on_configure","on_privmsg","on_notice");
        return @functions;
}

sub shutdown {
	foreach my $id (keys %dccs) {
		main::delete_socket($id);
	}
	%dccs = ();
}

sub before_configure {
	my ($self,$confname) = @_;
}

sub on_configure {
	my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
	return 1;
}

sub on_privmsg {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if ($text =~ /^\001DCC\sCHAT\schat\s(\d+)\s(\d+)\001$/i) {
		my $rawip = $1;
		my $port = $2;
		# clever slice trick to reverse the ip in place as we unpack it
		my $ip = join('.',(unpack("C4",pack("L",$rawip)))[3,2,1,0]);
		main::lprint("Dcc to decoded IP: $ip") if $main::debug;
		if ($target !~ /(\&|\#)/) {
			my $who = main::matcheshost($ident,$host);
			if ($who ne "") {
				main::lprint("DCC CHAT from $nick ($who): $ip:$port") if $main::debug;
				if (main::create_socket("dcc $nick $nid",$self,$ip,$port)) {
					$dccs{"dcc $nick $nid"}{nick} = $nick;
					$dccs{"dcc $nick $nid"}{lnick} = $who;
					$dccs{"dcc $nick $nid"}{network} = $nid;
					$dccs{"dcc $nick $nid"}{ip} = $ip;
					$dccs{"dcc $nick $nid"}{ident} = $ident;
					$dccs{"dcc $nick $nid"}{host} = $host;
					$dccs{"dcc $nick $nid"}{in} = 0;
					$dccs{"dcc $nick $nid"}{out} = 0;
					$dccs{"dcc $nick $nid"}{state} = 0;
					send_dcc("dcc $nick $nid","Please enter your password:");
				}
			} else {
				main::lprint("DCC from unknown user $nick!") if $main::debug;
			}
		}
	}
}

sub on_notice {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
}


1;
