# Please include this text with any bug reports
# $Id: socket.pm 10807 2008-11-15 15:42:06Z brain $
# =============================================

our %netid = ();
our %buffers = ();
our %amount_sent_this_interval = ();
our %customsockets = ();

sub init {
        die("This module may not be loaded from the configuration file");
}

use strict;
use IO::Select;
use MIME::Base64;
require 'modules/core/irc.pm';
no strict 'subs';

## API CALL: create_socket
# main::create_socket(id,module,host,port)
#
# Create a socket, which is inserted into the bot's socket engine. You must specify
# a port and host to connect to. The module and callback parameters indecate the module
# name to call back to when there is data waiting to be read from the socket. The id
# can be any arbitary text which your module can use to identify the socket.
# The function socket_callback will always be the called function within the module.
# Once you are finished with a socket you MUST delete it with main::delete_socket.
# this will transparently close the file descriptor for you. This function returns the
# file descriptor allocated, or 0 if it fails. You should avoid direct access to the
# file descriptor wherever possible.

sub create_socket {
        my ($id,$module,$host,$port) = @_;
        my $error = "";
        my $sin;
	my $fd;
	my $family = -1;
	my @res;
	my ($socktype, $proto, $saddr,$canonname) = ();
	lprint("Connecting create_socket: $id,$module,$host,$port") if $main::debug;
	eval {
		# This method is ipv6-safe when socket6 is loaded
		@res = getaddrinfo($host, $port, AF_UNSPEC, SOCK_STREAM);
		$family = -1;
		# This will take the first address to be returned from getaddrinfo(),
		# if there are multiple hosts they will be ignored. We can only connect
		# to one ip of a hostname anyway at a time, so it isnt worth going through
		# them with a preference for ipv4 or ipv6, the user specifies a host or
		# ip, they get what they get :)
		if (scalar(@res) >= 5) {
			($family, $socktype, $proto, $saddr, $canonname, @res) = @res;
			($host, $port) = getnameinfo($saddr, NI_NUMERICHOST | NI_NUMERICSERV);
			socket($fd, $family, $socktype, $proto);
			eval {
				lprint("Connecting to $host:$port...") if $main::debug;
				local $SIG{ALRM} = sub { lprint("Connection timed out") if $main::debug; $error = "Connection timed out" };
				alarm 3;
				connect($fd, $saddr);
				alarm 0;
				lprint("Connected!") if $main::debug;
			};
			if ($@) {
				$error = "Connection timed out!";
			}
		} else {
			$error = "Failed to resolve host!";
		}
	};
	if ($@) {
		$error = $@;
	}
	$SIG{ALRM} = sub { module_timers() };
	#alarm 1;
	if ($error eq "") {
		lprint("Connected!") if $main::debug;
	        $customsockets{$id}{module} = $module;
	        $customsockets{$id}{fd} = $fd;
		$customsockets{$id}{listener} = 0;
		return $customsockets{$id}{fd};
	} else {
		lprint("Not connected!") if $main::debug;
		return 0;
	}
}

sub create_listen_socket {
	my ($id,$module,$host,$port,$use_6) = @_;
        my $error = "";
        my $fd;
        lprint("Connecting create_listen_socket: $id,$module,$host,$port") if $main::debug;
	eval {
		if (!$use_6) {
		        socket($fd, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
			setsockopt($fd, SOL_SOCKET, SO_REUSEADDR, 1);
			if (defined $host) {
				my $my_addr = sockaddr_in($port, inet_aton($host));
				bind($fd,$my_addr);
			} else {
				my $my_addr = sockaddr_in($port, INADDR_ANY);
				bind($fd,$my_addr);
			}
			my $err = listen($fd,5);
			if (!$err) {
				die("Listen failed: $!");
			}
		} else {
                        socket($fd, PF_INET6, SOCK_STREAM, getprotobyname('tcp'));
                        setsockopt($fd, SOL_SOCKET, SO_REUSEADDR, 1);
                        if (defined $host) {
                                my $my_addr = sockaddr_in($port, inet_pton($host));
                                bind($fd,$my_addr);
                        } else {
                                my $my_addr = sockaddr_in($port, INADDR6_ANY);
                                bind($fd,$my_addr);
                        }
                        my $err = listen($fd,5);
                        if (!$err) {
                                die("Listen failed: $!");
                        }
		}
	};
        if ($@) {
                $error = $@;
        }
        if ($error eq "") {
                lprint("Listening!") if $main::debug;
                $customsockets{$id}{module} = $module;
                $customsockets{$id}{fd} = $fd;
		$customsockets{$id}{listener} = 1;
                return $customsockets{$id}{fd};
        } else {
                lprint("Not connected!") if $main::debug;
                return 0;
        }

}

## API CALL: write_socket
# write_socket(id,data)
#
# This call writes text to a socket you previously opened using main::create_socket.
# the id field must be the id of a created socket, and data can be any text or binary
# data you wish to send to the connection. The length of the data is calculated for
# you by the function.

sub write_socket {
	my ($id,$data) = @_;
	syswrite($customsockets{$id}{fd},$data,length($data));
}

## API CALL: read_socket
# read_socket(id)
#
# This call reads data from a socket which you have previously opened using the
# main::create_socket function. You should only use this function inside your
# socket's callback function, where you can gaurantee data is waiting to be read.
# if you call it outside this context, the socket will block the whole program
# until data becomes available for reading. If the function returns an empty
# string, the socket has closed and you should call main:: delete_socket to
# remove your socket id.
#
# NB: If you are within your callback function, you must usually read data,
# as data is pending, and will build up if not read until the sockets sendq
# exceeds!

sub read_socket {
	my ($id) = @_;
	my $buffer = "";
	my $result = sysread $customsockets{$id}{fd},$buffer,65535;
	if (($result == undef) || ($result = 0)) {
		return "";
	} else {
		return $buffer;
	}
}

## API CALL: delete_socket
# delete_socket(id)
#
# Deletes a socket from the custom sockets list, closing its descriptor.
# You must call this functiom when a read failure occurs on your socket.

sub delete_socket {
        my ($id) = @_;
	close($customsockets{$id}{fd});
        delete $customsockets{$id};
	return 1;
}

## Connect a socket to an IRC server.
#
# This function transparently handles both IPv6 and SSL and management of
# the socket engine hash %netid.
# Upon success a new entry is created in %netid (or an existing entry updated)
# and upon failure nothing is changed. This function may block for up to 3
# seconds upon a failed connection.

sub connect {
	my ($nid,$host,$port,$nick,$username,$gecos,$pass,$bindto,$use_ssl,$proxy_host,$proxy_port,$proxy_user,$proxy_password) = @_;
	my $orighost = $host;
	my $origport = $port;
	my $error = "";
	my $sin;
	my @res;
	my $family = -1;
	my ($socktype, $proto, $saddr,$canonname) = ();
	
	delete $main::reconnect{$nid};

        eval {
		if (defined $proxy_host) {
			lprint("Connecting to HTTP proxy server: [$proxy_host]:$proxy_port");
	                @res = getaddrinfo($proxy_host, $proxy_port, AF_UNSPEC, SOCK_STREAM);
		} else {
			lprint("Connecting directly to host: [$host]:$port");
			@res = getaddrinfo($host,$port, AF_UNSPEC, SOCK_STREAM);
		}
                $family = -1;
		# The getaddrinfo function will return a list of addresses. We arent going to try
		# and connect to them all, so just take the first with no preference between v4 and v6.
                if (scalar(@res) >= 5) {
                        ($family, $socktype, $proto, $saddr, $canonname, @res) = @res;
                        ($host, $port) = getnameinfo($saddr, NI_NUMERICHOST | NI_NUMERICSERV);
                        socket($netid{$nid}{handle}, $family, $socktype, $proto);
			# depending on if theyre binding to a v4 or v6 address, we have to call a different sockaddr_in*
			# function, its icky but its the most sensible way.
			if (defined($bindto)) {
				# The different protocols have different binding syntax. Its only
				# a slight difference but it was enough to have my tearing my hair
				# out for the better part of a saturday afternoon.
				lprint("Binding to $bindto...") if $main::debug;
				if ($bindto =~ /\:/) {
					lprint("...as a v6 address.") if $main::debug;
					bind($netid{$nid}{handle},sockaddr_in6(0,inet_pton(AF_INET6, $bindto)));
				} else {
					lprint("...as a v4 address.") if $main::debug;
					bind($netid{$nid}{handle}, sockaddr_in(0, inet_aton($bindto)));
				}
			}
                        eval {
                                lprint("Connecting to [$host]:$port...") if $main::debug;
                                local $SIG{ALRM} = sub { lprint("Connection timed out") if $main::debug; $error = "Connection timed out" };
                                alarm 3;
                                connect($netid{$nid}{handle}, $saddr);
				lprint("Connected!") if $main::debug;
                                alarm 0;
                        };
                        if ($@) {
                                $error = "Connection timed out!";
                        }
                } else {
                        $error = "Failed to resolve host!";
                }
        };
        if ($@) {
                lprint("$@");
        }

	if (defined $proxy_host) {
		lprint("HTTP proxy CONNECT: [$proxy_host]:$proxy_port -> [$orighost]:$origport");
		writeto($nid,"CONNECT $orighost:$origport HTTP/1.1");
		if (defined $proxy_user) {
			my $authorization = encode_base64("$proxy_user:$proxy_password");
			writeto($nid,"Proxy-Authorization: Basic $authorization\r\n");
		}
	}
	# if using ssl, initialize it
	if ($use_ssl) {
		if ($main::has_ssl) {
			lprint("Initializing ssl on connection $nid") if $main::debug;
			$netid{$nid}{ctx} = Net::SSLeay::CTX_new() or $error = "Failed to create SSL context object";
			Net::SSLeay::CTX_set_options($netid{$nid}{ctx}, &Net::SSLeay::OP_ALL);
			$netid{$nid}{ssl} = Net::SSLeay::new($netid{$nid}{ctx}) or $error = "Failed to create SSL object";
			Net::SSLeay::set_fd($netid{$nid}{ssl}, fileno($netid{$nid}{handle}));
			my $res = Net::SSLeay::connect($netid{$nid}{ssl});
			lprint("SSL Cipher for $nid: " . Net::SSLeay::get_cipher($netid{$nid}{ssl})) if $main::debug;
		} else {
			$error = "No Net::SSLeay!";
			lprint("You do not have Net::SSLeay installed! Please install this module then try again.");
		}
	}
	# if this network id exists, this will update it in the hash
	# otherwise it will create it.
	$main::received_pong{$nid} = 1;
	$netid{$nid}{lag} = 0;			# lag in seconds
	$netid{$nid}{is_ssl} = $use_ssl;	# ssl enabled? if so, {ssl} and {ctx} will be defined too
	$netid{$nid}{nick} = $nick;		# nickname for the connection
	$netid{$nid}{server} = $orighost;	# server canonical name
	$netid{$nid}{ip} = $host;		# server ip address
	$netid{$nid}{port} = $port;		# server port number
	$netid{$nid}{username} = $username;	# username (ident)
	$netid{$nid}{gecos} = $gecos;		# gecos (fullname field)
	$netid{$nid}{bind} = $bindto;		# ip bound to when connection was created
	$netid{$nid}{pass} = $pass;		# password used to connect or undef
	if ($error ne "") {
		my $t = (defined $main::reconnect_times{$nid} ? $main::reconnect_times{$nid} : 60);
		$main::reconnect{$nid} = time + $t;
		lprint("Connect to $nid failed, retry in $t secs") if $main::debug;
	} else {
		if ((defined $pass) && ($pass ne "")) {
			writeto($nid,"PASS $pass");
		}
		writeto($nid,"USER $username * * :$gecos");
		writeto($nid,"NICK $nick");
	}

	# clear the users list of ALL users from this network!
	my %copy_users = %main::nicks;
	foreach my $key (keys %copy_users) {
		if ((defined $main::nicks{$key}{network}) && ($main::nicks{$key}{network} eq $nid)) {
			trigger_on_del_record($nid,$main::nicks{$key}{nick},"");
			delete $main::nicks{$key};
		}
	}

	#alarm 1;

}

sub disconnect {
	my ($nid) = @_;
	close $netid{$nid}{handle};
}

sub write_fail ($) {
	my ($network) = @_;
	if (($netid{$network}{is_ssl}) && ($main::has_ssl)) {
		Net::SSLeay::free($netid{$network}{ssl});               # Tear down connection
        	Net::SSLeay::CTX_free($netid{$network}{ctx});
        }
	disconnect($network);
        my $t = (defined $main::reconnect_times{$network} ? $main::reconnect_times{$network} : 60);
        $main::reconnect{$network} = time + $t;
	lprint("write_fail: Network $network lost connection: '$!' will reconnect in $t secs") if $main::debug;
}

# writeto is limited to 256 bytes a second (0.25kb/sec) to prevent excess flood,
# however if the buffer is empty, all data in it is sent immediately.

sub writeto {
	my ($nid,$text) = @_;
	if (defined $netid{$nid}) {
		if (!defined $main::reconnect{$nid}) {
			$buffers{$nid} .= "$text\r\n";	
			lprint("$nid >> $text") if $main::debug;
			my $throttle = (defined $main::config{$nid}{throttlebps} ? $main::config{$nid}{throttlebps} : 256);
			if ((!defined $amount_sent_this_interval{$nid}) || ($amount_sent_this_interval{$nid} < $throttle)) {
				my ($start,$end) = split ('\r\n',$buffers{$nid},2);
				$buffers{$nid} = $end;
				if (length($start)) {
					if (($netid{$nid}{is_ssl}) && ($main::has_ssl)) {
						if (!Net::SSLeay::write($netid{$nid}{ssl}, "$start\r\n")) {
							write_fail($nid);
						}
						$amount_sent_this_interval{$nid} += length($start)+2;
					} else {
						if (!syswrite($netid{$nid}{handle},"$start\r\n",length($start)+2)) {
							write_fail($nid);
						}
						$amount_sent_this_interval{$nid} += length($start)+2;
					}
				}
			}
		} else {
			lprint("Cant write to network $nid, its down") if $main::debug;
		}
	} else {
		lprint("Cant write to nonexistent network $nid") if $main::debug;
	}
}

sub send_notice {
	my ($nid,$target,$text) = @_;
	$text = " " if ((!defined $text) || ($text eq ""));
	writeto($nid,"NOTICE $target :$text");
}

sub send_privmsg {
        my ($nid,$target,$text) = @_;
	$text = " " if ((!defined $text) || ($text eq ""));
        writeto($nid,"PRIVMSG $target :$text");
}

sub readfrom {
	my ($nid) = @_;
}

my $oldtime = time();

sub pollnetworks {
	my $sel = IO::Select->new();
	my $scount = 0;
	my $buffer = undef;
	my $old = time();
	foreach my $network (keys %netid) {
		# FIX: Dont attempt to select() a dead fd!
		if (!defined($main::reconnect{$network})) {
			$sel->add($netid{$network}{handle});
			$scount++;
		}
	}
        foreach my $sock (keys %customsockets) {
		$sel->add($customsockets{$sock}{fd});
		$scount++;
        }
	if ($scount == 0) {
		# no sockets to be read from, just wait 1 sec instead
		# and trigger the module timers
		sleep(1);
		module_timers();
	} else {
		if ($oldtime != time())
		{
			module_timers();
			$oldtime = time();
		}
		my @ready = $sel->can_read(1);
		if (scalar(@ready)>0) {
			foreach my $fd (@ready) {
				my %copycustomsockets = %customsockets;
				foreach my $sock (keys %copycustomsockets) {
					if ($fd == $customsockets{$sock}{fd}) {
						if ($customsockets{$sock}{listener} == 1) {
							# accept the new connection, give it a custom socket id.
							# notify the owner of the listening socket of their new
							# connection by providing this new socket id to it (which will
							# be random to avoid clashes with other named sockets created
							# by modules).
							my $identifier = "$sock" . "_" . generate_random_string(6);
							my $paddr = accept($customsockets{$identifier}{fd},$customsockets{$sock}{fd});
							eval "$customsockets{$sock}{module}"->socket_new($sock,$identifier,$paddr);
							main::lprint("Accepted new connection $identifier");
							$customsockets{$identifier}{module} = $customsockets{$sock}{module};
							$customsockets{$identifier}{listener} = 0;
						} else {
							eval {
								eval "$customsockets{$sock}{module}"->socket_callback($sock);
							};
						}
					}
				}
				foreach my $network (keys %netid) {
					if ((defined $main::reconnect{$network}) && ($main::reconnect{$network} == 0)) {
						delete $main::reconnect{$network};
					}
					if (($fd == $netid{$network}{handle}) && (!defined($main::reconnect{$network}))) {
						my $result = 0;
						if (($netid{$network}{is_ssl}) && ($main::has_ssl)) {
							$buffer = Net::SSLeay::read($netid{$network}{ssl});
							if (!defined $buffer) {
								undef $result;
							} else {
								$result = 1;
							}
						} else {
							$result = sysread $netid{$network}{handle},$buffer,65535;
						}
						if ((!defined $result) || ($result == 0)) {
							disconnect($network);
							if (($netid{$network}{is_ssl}) && ($main::has_ssl)) {
								Net::SSLeay::free($netid{$network}{ssl});		# Tear down connection
								Net::SSLeay::CTX_free($netid{$network}{ctx});
							}
							my $t = (defined $main::reconnect_times{$network} ? $main::reconnect_times{$network} : 60);
							$main::reconnect{$network} = time + $t;
                                                        lprint("read: Network $network lost connection: '$!', will reconnect in $t secs") if $main::debug;
						} else {
							$netid{$network}{buffer} .= $buffer;
							if ($netid{$network}{buffer} =~ /\n$/) {
								# the receive buffer ends in a \n, so process it all
								my @lines = split('\n',$netid{$network}{buffer});
								foreach my $line (@lines) {
									chop($line);
									lprint("$network << $line") if $main::debug;
									process($network,$line);
								}
								$netid{$network}{buffer} = "";
							}
						}
					}
				}
			}
		}
	}
	if ($old != time()) {
		module_timers();
	}
}

1;
