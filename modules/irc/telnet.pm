# Please include this text with any bug reports
# $Id: telnet.pm 1926 2005-11-10 14:57:56Z brain $
# =============================================

package modules::irc::telnet;

my %telnets;

my $bind_use_v6 = 0;
my $bind_host = "*";
my $bind_port = "3000";

sub init {
	my($self) = @_;
}

sub send_tel {
	my ($id,$text) = @_;
	main::lprint("TELOUT $id: $text") if $main::debug;
	$text .= "\r\n";
	main::write_socket($id,$text);
	$telnets{$id}{out} += length($text);
}

sub socket_new {
	my($self,$listener,$newsock,$paddr) = @_;
	$telnets{$newsock}{nick} = "";
	$telnets{$newsock}{ident} = "";
	$telnets{$newsock}{hostname} = "";
	$tenlets{$newsock}{network} = "";
	$telnets{$newsock}{state} = 0;
	$telnets{$newsock}{out} = 0;
	$telnets{$newsock}{in} = 0;
	send_tel($newsock,"Username:");
}

sub socket_callback {
	my ($self,$id) = @_;
	my $result = main::read_socket($id);
	$telnets{$id}{in} += length($result);
	if ($result eq "") {
		main::lprint("telnet Connection '$id' failed") if $main::debug;
		main::delete_socket($id);
		main::lprint("Deleted socket") if $main::debug;
		delete $telnets{$id};
		return;
	} else {
		chomp($result);
		$result =~ s/(\r|\n)//g;
		if ($result eq "") { return };
		main::lprint("telnet Data on '$id': '$result'") if $main::debug;
		if ($telnets{$id}{state} == 0) {
			$telnets{$id}{nick} = $result;
			send_tel($id,"Password:");
			$telnets{$id}{state} = 1;
		} elsif ($telnets{$id}{state} == 1) {
			# check user/pass
			# close connection if its wrong otherwise advance to state 2.
			my $n = $telnets{$id}{nick};
			main::lprint("telnet user/pass validation for '$n'") if $main::debug;
			if ((main::userexists($telnets{$id}{nick})) && (main::comparepassword($telnets{$id}{nick},$result))) {
				main::lprint("telnet user/pass validation success for '$n'") if $main::debug;
				$telnets{$id}{state} = 2;
				send_tel($id,"Login successful, $n");
				# now if the user is on irc... we just give them the logged in state. otherwise, we kludge
				# a user record in.
				my $found_real_user = 0;
				foreach my $nref (%main::nicks) {
					my ($tnet,$tnick) = split(",",$nref);
					if (lc($tnick) eq lc($telnets{$id}{nick})) {
			                        $main::nicks{$nref}{login} = $telnets{$id}{nick};
						$telnets{$id}{network} = $tnet;
						$found_real_user = 1;
			                        my @clist = main::get_chanlist($nid,$nick);
			                        foreach my $channel (@clist) {
			                                $main::nicks{$nref}{lc($channel)}{flags}  = $main::users{$telnets{$id}{nick}}{FLAGS}{$nid}{lc($channel)};
			                                $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{_}{_};
			                                $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{$nid}{_};
			                                $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{_}{lc($channel)};
			                                $main::nicks{$nref}{lc($channel)}{flags}  = trim($main::nicks{$nref}{lc($channel)}{flags});
			                        }
						main::lprint("Logged in irc-visible user $nref") if $main::debug;
					}
				}
				if (!$found_real_user) {
					# find the bot's first network and just log them in here
					my $net = "";
					foreach my $nwn (%main::netids) {
						$net = $nwn;
					}
					my $nref="$net,$n";
					$main::nicks{$nref}{login} = $telnets{$id}{nick};
					$main::nicks{$nref}{ident} = "unknown";
					$main::nicks{$nref}{host} = "telnet";
					$telnets{$id}{network} = $net;
				        my @chans = split(' ',$main::config{$net}{channels} . $main::config{_}{channels});
				        foreach my $channel (@chans) {
		                                $main::nicks{$nref}{lc($channel)}{flags}  = $main::users{$telnets{$id}{nick}}{FLAGS}{$net}{lc($channel)};
			                        $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{_}{_};
		                                $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{$net}{_};
		                                $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$telnets{$id}{nick}}{FLAGS}{_}{lc($channel)};
		                                $main::nicks{$nref}{lc($channel)}{flags}  = trim($main::nicks{$nref}{lc($channel)}{flags});
				        }
					main::lprint("Logged in non-visible user $nref") if $main::debug;
				}
			} else {
				main::lprint("telnet Connection '$id' invalid password for '$n'") if $main::debug;
				send_tel($id,"Invalid username or password.");
				main::delete_socket($id);
				delete $telnets{$id};
			}
		} elsif ($telnets{$id}{state} == 2) {
			if ($result =~ /^\./) {
				$result =~ s/^\.//;
				handle_command($id,$result);
			}
                        my $nref  = "$telnets{$id}{network},$telnets{$id}{nick}";
                        if ($main::nicks{$nref}{login} eq "") {
                                send_tel($id,"Logged out -- closing connection.");
                                main::delete_socket($id);
                                delete $telnets{$id};
			}
		}
	}
}

sub handle_command {
	my ($id,$text) = @_;
	my @params = split(' ',$text);
	my $command = shift @params;
	main::lprint("handle command $command in telnet") if $main::debug;
	my @return = main::do_command($telnets{$id}{network},$telnets{$id}{nick},$telnets{$id}{ident},$telnets{$id}{host},$command,@params);
	foreach my $line (@return) {
		send_tel($id,$line);
	}
}

sub implements {
        my @functions = ("on_configure","after_configure");
        return @functions;
}

sub after_configure
{
	my $self = $_[0];
	main::create_listen_socket("telnet_main",$self,$bind_host,$bind_port,$bind_use_v6);
}

sub on_configure
{
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
        if ($configline =~ /^telnet\s+"(.+)"\s+"(.+?)"$/i) {
                if ($net_context ne "_") {
                        main::lprint("telnet command cannot be inside a network context on $configfile:$linenumber");
                        return 0;
                }
		my $ipport = $1;
		my $proto = $2;
		$bind_use_v6 = ($proto =~ /6/);
		($bind_host,$bind_port) = split("/",$ipport,2);
		if ($bind_host eq "*") {
			undef $bind_host;
		}
		if ($bind_port eq "*") {
			undef $bind_port;
		}
	}
	return 1;
}

sub shutdown {
	foreach my $id (keys %telnets) {
		main::delete_socket($id);
	}
	%telnets = ();
	main::delete_socket("telnet_main");
}

1;
