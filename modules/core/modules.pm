# Please include this text with any bug reports
# $Id: modules.pm 12792 2014-07-10 08:04:48Z brain $
# =============================================

use strict;
no strict 'refs';
use Symbol qw(delete_package);

sub init {
        die("This module may not be loaded from the configuration file");
}

our @modlist = ();
our @modfiles = ();

our %mod_functions = ();
our %mod_timers = ();

my $secs = 0;

# Load all modules.
# This function will load every module specified in the config file
# by first trying to 'require' it. Once it has required it, it will
# then map its filename to a namespace name (e.g. modules/core/a.pm
# to modules::core::a) then call each modules init() method.
# It will then call each modules 'implements()' method which returns
# an array of methods which this module implements, meaning that
# a module does not need to have stubs for functions it does not
# make use of, unlike IRC Defender's module system which the initial
# idea for this came from.

sub loadmodules {
	@modlist = ();
	%mod_functions = ();
	foreach my $module (@main::modules) {
		lprint("Load module: $module") if $main::debug;
		eval {
			require "$module";
		};
		if ($@) {
			lprint("ERROR! Could not load $module: $@");
		} else {
			push @modfiles, $module;
			$module =~ s/\/|\\/::/g;
			$module =~ s/\.pm$//g;
			push @modlist, $module;
			eval "$module->init()";
			if ($@) {
				pop @modlist;
				pop @modfiles;
				my $error = "$@";
				if ($error =~ /Can\'t locate object method/) {
					$error = "This is not a valid botnix module! Error is: '$error'";
				}
				lprint("ERROR! Could not load $module: $error");
			} else {
				my @implements = $module->implements();
				foreach my $function (@implements) {
					$mod_functions{$module}{$function} = 1;
				}
			}
		}
	}
	# use only the successfully loaded list...
	@main::modules = @main::modlist;
}

sub unload_all_modules {
	lprint("Unloading all modules...");
	foreach my $module (@main::modules) {
		$module->shutdown();
		eval "no $module;";
#		delete_package($module);
	}
	@main::modules = ();
	@main::modlist = ();
	%main::mod_functions = ();
}

sub module_timers {
	$secs++;
        foreach my $timer (keys %mod_timers) {
		if (($secs % $mod_timers{$timer}{interval}) == 0) {
			my $trigger = $mod_timers{$timer}{module} . "->" . $mod_timers{$timer}{sub} . "();";
			eval $trigger;
		}
        }
        foreach my $network (keys %main::reconnect) {
                if ((time > $main::reconnect{$network}) && ($main::reconnect{$network} != 0)) {
                        $main::reconnect{$network} = 0;
                        my @addresses = split(' ',$main::config{$network}{addresses});
                        my $address_to_use = $addresses[rand(@addresses)-1];
                        my ($server,$port) = split('/',$address_to_use);
                        &connect($network,$server,$port,$main::config{$network}{nickname},$main::config{$network}{ident},$main::config{$network}{gecos},$main::config{$network}{password},$main::config{$network}{bind},$main::config{$network}{ssl},$main::config{$network}{proxy_host},$main::config{$network}{proxy_port},$main::config{$network}{proxy_user},$main::config{$network}{proxy_pass});
	        }
	}
	flush_mode_queue();
	foreach my $nid (keys %main::buffers) {
		$main::amount_sent_this_interval{$nid} = 0;
                my ($start,$end) = split ('\r\n',$main::buffers{$nid},2);
                $main::buffers{$nid} = $end;
		if (length($start)) {
                        if (($main::netid{$nid}{is_ssl}) && ($main::has_ssl)) {
                                if (!Net::SSLeay::write($main::netid{$nid}{ssl}, "$start\r\n")) {
					write_fail($nid);
				}
                                $main::amount_sent_this_interval{$nid} += length($start)+2;
                        } else {
                                if (!syswrite($main::netid{$nid}{handle},"$start\r\n",length($start)+2)) {
					write_fail($nid);
				}
                                $main::amount_sent_this_interval{$nid} += length($start)+2;
                        }
		}
	}
        if (($secs % 60) == 0) {
		my $now = time();
                savestorefile($main::storefile);
                foreach my $network (keys %main::netid) {
                        if ((!$main::received_pong{$network}) && (!defined $main::reconnect{$network})) {
				#lprint("$network not replied to last ping, disconnecting") if $main::debug;
				#write_fail($network);
                        } else {
				if (!defined $main::reconnect{$network}) {
	                                writeto($network,"PING :".$main::netid{$network}{server});
					$main::received_pong{$network} = 0;
					$main::netid{$network}{lastping} = $now;
                        	}
			}
                }
        }
	#alarm 1;
}

sub create_timer {
	my ($id,$module,$sub,$interval) = @_;
	$mod_timers{$id}{module} = $module;
	$mod_timers{$id}{sub} = $sub;
	$mod_timers{$id}{interval} = $interval;
}

sub delete_timer {
	my ($id) = @_;
	delete $mod_timers{$id};
}

sub trigger_before_configure {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{before_configure}) {
			$module->before_configure(@_);
		}
	}
}

sub trigger_on_configure {
	my $ret = 0;
	my $rv = 1;
	my $failure = "";
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_configure}) {
			$ret = $module->on_configure(@_);
			if (!$ret) {
				$failure = $module;
				$rv = 0;
			}
		}
	}
	if (!$rv) {
		print "\n\nModule '$failure' failed configuration!\n";
	}
	return $rv;
}

sub trigger_after_configure {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{after_configure}) {
			$module->after_configure(@_);
		}
	}
}



sub trigger_on_raw {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_raw}) {
			$module->on_raw(@_);
		}
	}
}

sub trigger_on_privmsg {
        foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_privmsg}) {
			$module->on_privmsg(@_);
		}
        }
}

sub trigger_on_notice {
        foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_notice}) {
	                $module->on_notice(@_);
		}
        }
}

sub trigger_on_kick {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_kick}) {
			$module->on_kick(@_);
		}
	}
}

sub trigger_on_join {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_join}) {
                        $module->on_join(@_);
                }
        }
}

sub trigger_on_quit {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_quit}) {
                        $module->on_quit(@_);
                }
        }
}

sub trigger_on_nick{
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_nick}) {
                        $module->on_nick(@_);
                }
        }
}

sub trigger_on_part {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_part}) {
                        $module->on_part(@_);
                }
        }
}

sub trigger_on_mode {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_mode}) {
			$module->on_mode(@_);
		}
	}
}

sub trigger_on_single_mode {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_single_mode}) {
			$module->on_single_mode(@_);
		}
	}
}

sub trigger_on_set_record {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_set_record}) {
                        $module->on_set_record(@_);
                }
        }
}


sub trigger_on_add_record {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_add_record}) {
                        $module->on_add_record(@_);
                }
        }
}

sub trigger_on_del_record {
        foreach my $module (@main::modules) {
                if ($mod_functions{$module}{on_del_record}) {
                        $module->on_del_record(@_);
                }
        }
}

sub emit {
	my ($what,$eventid,@params) = @_;
	trigger_on_emit($what,$eventid,@params) if defined $eventid;
}

sub trigger_on_emit {
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_emit}) {
			$module->on_emit(@_);
		}
	}
}

sub trigger_on_command {
	my @return = ();
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_command}) {
			@return = $module->on_command(@_);
			if ((scalar(@return) > 0) && ($return[0] ne "")) {
				return @return;
			}
		}
	}
	lprint("Empty return") if $main::debug;
	return ();
}

sub lprint {
	my $logged = 0;
	
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_log}) {
			$module->on_log(@_);
			$logged = 1;
		}
	}
	if ((!$logged) || ($main::debug) || ($main::during_config)) {
		print "\n\n" if $main::during_config;
		print join(' ',@_) . "\n";
	}
}

sub lprint_directed {
	my $logged = 0;
	my ($command,$nick,$net,$channel,@text) = @_;
	foreach my $module (@main::modules) {
		if ($mod_functions{$module}{on_log_directed}) {
			$module->on_log_directed($command,$nick,$net,$channel,@text);
			$logged = 1;
		}
	}
	if ((!$logged) || ($main::debug)) {
		print "<$net/$channel> $nick '$command' -> '" . join(' ',@text) . "'\n";
	}
}

1;
