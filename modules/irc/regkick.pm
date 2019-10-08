# Please include this text with any bug reports
# $Id: regkick.pm 1898 2005-10-01 16:09:29Z brain $
# =============================================

package modules::irc::regkick;

my %regkicks = ();
my $self = $me;

sub init {
	my ($me) = @_;
	$self = $me;

	# add our help sections to the help system
	main::add_help_commands("Channel Commands",("REGKICK","REGUNKICK","REGLIST"));
	main::add_context_help("REGKICK","Syntax: REGKICK [network] <#channel> <regexp> <reason>\nAdd a regexp kickban."); 
	main::add_context_help("REGUNKICK","Syntax: REGUNKICK [network] <#channel> <regexp> <reason>\nDelete a regexp kickban.");
        main::add_context_help("REGLIST","Syntax: REGLIST\nShows all regexp kickbans");

	# re-read all our persistent data from the backing store
        %regkicks = main::get_all_items($self);

	main::add_command("REGKICK",$self."::handle_regkick");
	main::add_command("REGUNKICK",$self."::handle_regunkick");
	main::add_command("REGLIST",$self."::handle_reglist");
}

sub implements {
        my @functions = ("on_join");
        return @functions;
}

sub shutdown {
	my ($self)= @_;
	main::del_help_commands("Channel Commands",("REGLIST","REGKICK","REGUNKICK"));
	main::del_context_help("REGKICK");
	main::del_context_help("REGUNKICK");
	main::del_context_help("REGLIST");

        main::del_command("REGKICK");
        main::del_command("REGUNKICK");
        main::del_command("REGLIST");
}


sub on_join {
        my ($self,$nid,$server,$nick,$ident,$host,$target)= @_;
	foreach my $nerd (keys %regkicks) {
		my ($network,$channel,$regkick) = split(',',$nerd,3);
		my $reason = $regkicks{$nerd};
		if (("$nick!$ident\@$host" =~ /$regkick/i) && ($nid eq $network) && (lc($target) eq lc($channel))) {
	                my $nref2 = "$nid,$nick";
	                main::add_mode_queue($nid,$target,"+b","*!$ident\@$host");
		        main::writeto($nid,"KICK $target $nick :REGKICK: $reason");
		}
	}
}

sub handle_regkick {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = lc($target);
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = lc(shift @params);
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
	my $regkick = shift @params;
        my $reason = join(' ',@params);
        $regkicks{"$network,$channel,$regkick"} = $reason;
        main::store_item($self,"$network,$channel,$regkick",$reason);
        return ("Added regular expression kickban \002$regkick\002 to \002$network/$channel\002 ($reason)");
}

sub handle_regunkick {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = lc($target);
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = lc(shift @params);
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"operator",$network,$channel)) {
                return ("You do not have the operator flag on \002$network/$channel\002");
        }
	my $regkick = shift @params;
        delete $regkicks{"$network,$channel,$regkick"};
        main::remove_item($self,"$network,$channel,$regkick");
        return ("Deleted regular expression kickban \002$regkick\002 from \002$network/$channel\002");
}

sub handle_reglist {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"owner",$network,$channel)) {
		return ("You must have owner status for this command!");
        }
	my @return = ();
        my $header = "\002".sprintf("%-10s","NETWORK").sprintf("%-15s","CHANNEL").sprintf("%-40s","REGEXP").sprintf("%-40s","REASON");
        push @return, $header;
        foreach my $key (keys %regkicks) {
		my ($network,$channel,$regkick) = split(',',$key,3);
                push @return, sprintf("%-10s",$network).sprintf("%-15s",$channel).sprintf("%-40s",$regkick).sprintf("%-40s",$regkicks{$key});
        }
        return @return;
}

1;
