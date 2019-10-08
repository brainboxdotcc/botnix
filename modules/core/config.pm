# Please include this text with any bug reports
# $Id: config.pm 8495 2007-11-04 14:58:15Z om $
# =============================================

use strict;

sub init {
        die("This module may not be loaded from the configuration file");
}

require 'modules/core/modules.pm';

our %config = ();
our %channelflags = ();
our %maxmodes = ();
our %reconnect_times = ();
our @modules = ();
our $during_config = 0;
my @configfile = ();
my $count = 0;

sub validident {
	my $ident = $_[0];
	return ($ident =~ /^[A-Z\.\-0-9_]{1,12}$/i);
}

sub validaddress {
	my $address = $_[0];
	return ($address =~ /^[A-Z0-9\.\-\:]{1,64}\/\d+$/i);
}

sub validnick {
	my $nick = $_[0];
	return ($nick =~ /^[A-Za-z\[\]\{\}^\\|\_\-`][A-Za-z0-9\[\]\{\}^\\|\_\-`]{0,31}$/);
}

sub trim {
	my $string = shift;
	for ($string) {
		s/^\s+//;
		s/\s+$//;
	}
	return $string;
}

sub config_getline {
	my ($linenumber) = @_;
	return $configfile[$linenumber];
}

sub config_setcurrentline {
	$count = $_[0];
}

sub config_next {
	$count++;
}

sub config_last {
	$count--;
}

sub config_current {
	return $count;
}

sub readconfig {
	$during_config = 1;
	my ($confname,$loadmodules) = @_;
	open(CONF,"<$confname") or lprint("Cannot open config file $confname: $!");
	my $network = "_";
	my $channel = "";
	$count = 0;
	my $line = "";
	%config = ();
	@configfile = ();
	%channelflags = ();
	%maxmodes = ();
	%reconnect_times = ();
	if ($loadmodules) {
		@modules = ();
	}
	trigger_before_configure($confname);
	while ($line = <CONF>) {
		if (defined $line) {
			chomp($line);
			$line = trim($line);
			if ($line ne "") {
				if ($line eq "{") {
					## If the user put a { on a line on its own,
					# append it to the last line instead.
					my $old_line = pop @configfile;
					$old_line .= " {";
					push @configfile, $old_line;
				} else {
					## just a line, nothing to see here, move along
					push @configfile, $line;
				}
			}
		} else {
			next;
		}
	}
	close(CONF);
	while ($count < scalar(@configfile)) {
		$line = $configfile[$count];
		my $repeater = 0;
		if ($line =~ /^(\w+)\s+"(.+?)"\s+{$/i) {
			my $blockname = $1;
			my $blockval = $2;
			my $size = 0;
			if ($loadmodules) {
				if (($blockname !~ /^network$/) && ($1 !~ /^channel$/)) {
					lprint("Skipping unknown block type '$blockname' of value '$blockval' for first pass") if $main::debug;
					while ($configfile[$count] ne "}") {
						$count++;
						$size++;
					}
					$count++;
					lprint("Unknown block of size $size skipped on first pass.") if $main::debug;
					next;
				}
			}
		}
		if ($line =~ /^network\s+"(.+?)"\s+\{$/i) {
			# within network context
			my $newnet = $1;
			if ($network ne "_") {
				lprint("Already in context of network $network at $confname:$count");
				$during_config = 0;
				return 0;
			}
			if ($network =~ /(\,|\s|\|)/) {
				lprint("Illegal character in network name at $confname:$count");
				$during_config = 0;
				return 0;
			}
			$network = $newnet;
                }elsif ($line =~ /^(\/\/|\#)(.+?)$/i) {
		# comment
                }elsif ($line =~ /^rejoin$/i) {
			# rejoin on kick
                        if ($channel eq "") {
                                lprint("Channel flag outside of channel context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			$channelflags{$network}{lc($channel)}{rejoin} = 1;
                }elsif ($line =~ /^cycle$/i) {
			# cycle if no ops
                        if ($channel eq "") {
                                lprint("Channel flag outside of channel context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			$channelflags{$network}{lc($channel)}{cycle} = 1;
                }elsif ($line =~ /^autovoice$/i) {
			# auto voice everyone
                        if ($channel eq "") {
                                lprint("Channel flag outside of channel context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			$channelflags{$network}{lc($channel)}{autovoice} = 1;
		}elsif ($line =~ /^channel\s+"(.+?)"\s+\{$/i) {
			# within channel context
			my $newchan = $1;
			if ($channel ne "") {
				lprint("Already in context of channel $channel at $confname:$count");
                                $during_config = 0;
				return 0;
			}
			$channel = $newchan;
			$config{$network}{channels} .= "$channel ";
		}elsif ($line =~ /^module\s+"(.+?)"$/i) {
			if ($loadmodules) {
				# load a module - should not be in a network or channel context
				if (($channel ne "") || ($network ne "_")) {
					lprint("module command within a network or channel context at $confname:$count");
	                                $during_config = 0;
					return 0;
				}
				push @modules, $1;
			}
		}elsif ($line =~ /^userfile\s+"(.+?)"$/i) {
			$main::userfile = $1;
		}elsif ($line =~ /^storefile\s+"(.+?)"$/i) {
			$main::storefile = $1;
		}elsif ($line =~ /^password\s+"(.+?)"$/i) {
			# password - valid within network context
			# can only be one per network
                        if ($network eq "_") {
                                lprint("password value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{password})) {
                                lprint("password for network $network is already defined at $confname:$count");
				$during_config = 0;
                                return 0;
                        }
                        my $pass = $1;
                        $config{$network}{password} = $pass;
		}elsif ($line =~ /^reconnect\s+"(.+?)"$/i) {
			# reconnect - valid within network context
			# can only be one per network
			if ($network eq "_") {
				lprint("reconnect value outside of network context at $confname:$count");
				$during_config = 0;
				return 0;
			}
			if (defined($reconnect_times{$network})) {
				lprint("reconnect for network $network is already defined at $confname:$count");
				$during_config = 0;
				return 0;
			}
			$reconnect_times{$network} = $1;
                }elsif ($line =~ /^ident\s+"(.+?)"$/i) {
                        # ident - valid within network context
			# can be only one per network
                        if ($network eq "_") {
                                lprint("ident value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{ident})) {
                                lprint("ident for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			my $ident = $1;
                        if (!validident($ident)) {
                                lprint("ident value '$ident' invalid at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			$config{$network}{ident} = $ident;
                }elsif ($line =~ /^fullname\s+"(.+?)"$/i) {
                        # fullname - valid within network context
                        # can be only one per network
                        if ($network eq "_") {
                                lprint("fullname value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{gecos})) {
                                lprint("fullname for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        my $gecos = $1;
                        $config{$network}{gecos} = $gecos;
                }elsif ($line =~ /^bind\s+"(.+?)"$/i) {
                        # bind - valid within network context
                        # can be only one per network - *OPTIONAL*
                        if ($network eq "_") {
                                lprint("bind value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{bind})) {
                                lprint("bind for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        my $bind = $1;
                        $config{$network}{bind} = $bind;
		}elsif ($line =~ /^proxyaddress\s+"(.+?)"$/i) {
                        # proxyaddress - valid within network context
                        # can be only one per network - *OPTIONAL*
                        if ($network eq "_") {
                                lprint("proxyaddress value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{proxy_host})) {
                                lprint("proxyaddress for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        my $proxy = $1;
			$proxy =~ /(.+?)\/(\d+)/;
			($config{$network}{proxy_host},$config{$network}{proxy_port}) = ($1,$2);
		}elsif ($line =~ /^proxyauth\s+"(.+?)"\s+"(.+?)"$/i) {
                        # proxyauth - valid within network context
                        # can be only one per network - *OPTIONAL*
                        if ($network eq "_") {
                                lprint("bind value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        if (defined($config{$network}{proxy_user})) {
                                lprint("proxyauth for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        my $proxy_user = $1;
			my $proxy_pass = $2;
			($config{$network}{proxy_user},$config{$network}{proxy_pass}) = ($proxy_user,$proxy_pass);
                }elsif ($line =~ /^address\s+"(.+?)"$/i) {
                        # address - valid within network context
			# can be one or more per network
                        if ($network eq "_") {
                                lprint("address value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			my $addr = $1;
			if (!validaddress($addr)) {
				lprint("address value '$addr' invalid at $confname:$count");
                                $during_config = 0;
				return 0;
			}
			$config{$network}{addresses} .= "$addr ";
		}elsif ($line =~ /^usessl\s+"(.+?)"$/i) {
			# usessl - set to yes, 1, etc to enable ssl on this network connection.
			# can be only one per network.
			if ($network eq "_") {
				lprint("usessl value outside of network context at $confname:$count");
                                $during_config = 0;
				return 0;
			}
			my $usessl = $1;
			if (defined($config{$network}{ssl})) {
				lprint("usessl for network $network is already defined at $confname:$count");
                                $during_config = 0;
				return 0;
			}
			$config{$network}{ssl} = (($usessl =~ /^yes$/) || ($usessl =~ /1/) || ($usessl =~ /^true$/));
                }elsif ($line =~ /^throttlebps\s+"(.+?)"$/i) {
                        # address - valid within network context
                        if ($network eq "_") {
                                lprint("throttlebps value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
                        $config{$network}{throttlebps} .= "$1";
		}elsif ($line =~ /^maxmodes\s+"(.+?)"$/i) {
			# maxmodes - valid within network context
			# can only be one per network, defaults to 3
			if ($network eq "_") {
				lprint("address value outside of network context at $confname:$count");
                                $during_config = 0;
				return 0;
			}
			$maxmodes{$network} = $1;
                }elsif ($line =~ /^nickname\s+"(.+?)"$/i) {
                        # nickname - valid within network context
                        # can be only one per network
                        if ($network eq "_") {
                                lprint("address value outside of network context at $confname:$count");
                                $during_config = 0;
                                return 0;
                        }
			if (defined($config{$network}{nickname})) {
                                lprint("nickname for network $network is already defined at $confname:$count");
                                $during_config = 0;
                                return 0;
			}
			my $nick = $1;
                        if (!validnick($nick)) {
                                lprint("nick value '$nick' invalid at $confname:$count");
                                $during_config = 0;
				return 0;
                        }
			$config{$network}{nickname} = $nick;
		} elsif ($line =~ /^}$/) {
			if ($channel ne "") {
				# leaving channel context
				$channel = "";
			} elsif ($network ne "_") {
				# leaving network context
				$network = "_";
			} else {
				# no context
				lprint("Not in channel or network context at $confname:$count");
                                $during_config = 0;
				return 0;
			}
		} else {
			if ($line ne "") {
				$repeater = 0;
				my $oldline = $count;
				my $result = trigger_on_configure($network,$channel,$confname,$count,$line);
				if (!$result) {
	                                $during_config = 0;
					return 0;
				}
				if ($oldline != $count) {
					# the module parsed a block
					$repeater = 1;
				}
			}
		}

		# This is a sanity check to check for unknown blocks that modules dont parse

		if (($line =~ /^(\w+)\s+"(.+?)"\s+{$/i) && (!$repeater)) {
			my $blockname = $1;
			my $blockval = $2;
			my $size = 0;
			if (!$loadmodules) {
				if (($blockname !~ /^network$/) && ($1 !~ /^channel$/)) {
					print "Unknown block type '$blockname' in $confname:$count (\"$blockval\")\nDid you forget to load the module which recognises block type '$blockname'?\n";
	                                $during_config = 0;
					return 0;
				}
			}
		}

		config_next();
	}
	trigger_after_configure($confname,$count);
        $during_config = 0;
	return 1;
}

1;
