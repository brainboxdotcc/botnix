# Please include this text with any bug reports
# $Id: floatinglimit.pm 1838 2005-09-20 11:37:39Z brain $
# =============================================

package modules::irc::floatinglimit;

my %float = ();

sub init {
	my ($self) = @_;
	main::create_timer("floating_limit_timer",$self,"float_me",60);
}

sub implements {
        my @functions = ("before_configure","on_configure");
        return @functions;
}

sub shutdown {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
	main::delete_timer("floating_limit_timer");
}

sub float_me {
	foreach my $data (keys %float) {
		my ($net,$chan) = split(',',$data);
		my @users = main::get_members($net,$chan);
		my $user_float = $float{$data} + scalar(@users);
		# only send the modechange if the limit is not already equal to the float
		# (winbot never tracked this, so badly behaved servers displayed the limit 
		# over and over)
		if ($net eq "_") {
			foreach my $net (keys %main::netid) {
				if ($main::chanmodes{$net}{lc($chan)}{limit} != $user_float) {
					main::add_mode_queue($net,$chan,"+l",$user_float);
				}
			}
		} else {
			if ($main::chanmodes{$net}{lc($chan)}{limit} != $user_float) {
				main::add_mode_queue($net,$chan,"+l",$user_float);
			}
		}
	}
}

sub before_configure {
        my ($self,$confname) = @_;
}

sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
        if ($configline =~ /^floatinglimit\s+"(.+)"$/i) {
                if ($chan_context eq "") {
                        main::lprint("floatinglimit command outside of channel context on $configfile:$linenumber");
                        return 0;
                }
		$chan_context = lc($chan_context);
                $float{"$net_context,$chan_context"} = $1;
        }
	return 1;
}


1;
