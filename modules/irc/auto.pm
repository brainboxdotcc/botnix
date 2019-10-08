# Please include this text with any bug reports
# $Id auto.pm 2 2007-07-21 02:15:29Z StarG $
# =============================================

# Module by StarG

package modules::irc::auto;

my %auto = ();
my $self = "";

my $debug_module = 0;

#use strict;

my $curr_channel = "";
my $curr_user = "";
my $curr_operation = "";

sub init {
	my ($me) = @_;
	$self = $me;

	# add our help sections to the help system
	main::add_help_commands("Channel Commands",("ADDAUTO","DELAUTO","LISTAUTO"));
	main::add_context_help("ADDAUTO","Syntax: ADDAUTO [network] <#channel> <user> <operation> <reason>\nAdd an automatic operation to the user on the channel on join."); 
	main::add_context_help("DELAUTO","Syntax: DELAUTO [network] <#channel> <user> <operation> <reason>\nRemove an automatic operation.");
        main::add_context_help("LISTAUTO","Syntax: LISTAUTO\nShows all automatic operations.");

	# re-read all our persistent data from the backing store
        %auto = main::get_all_items($self);

	main::add_command("ADDAUTO",$self."::handle_addauto");
	main::add_command("DELAUTO",$self."::handle_delauto");
	main::add_command("LISTAUTO",$self."::handle_listauto");
}

sub implements {
        my @functions = ("on_join","on_raw");
        return @functions;
}

sub shutdown {
	my ($self)= @_;
	main::del_help_commands("Channel Commands",("ADDAUTO","DELAUTO","LISTAUTO"));
	main::del_context_help("ADDAUTO");
	main::del_context_help("DELAUTO");
	main::del_context_help("LISTAUTO");

        main::del_command("ADDAUTO");
        main::del_command("DELAUTO");
        main::del_command("LISTAUTO");
}


sub on_join {
        my ($self,$nid,$server,$nick,$ident,$host,$target)= @_;
	
	foreach my $nerd (keys %auto) {
		my ($network,$channel,$username,$operation) = split(',',$nerd,4);
		my $reason = $auto{$nerd};

		# lets look up the hostmask for the entered usernick 
		my $user = matcheshostandnick("$ident","$host",$nick);	
		
		# found user in the userlist, matches the user from the host and matches the actual nickname... thats what we wanted to make sure
		if ( lc $user eq lc $username && lc $user eq lc $nick )
		{
		    # check wheter (s)he is on the right channel too 
		    if (($nid eq $network) && (lc($target) eq lc($channel))) {
    
			# store the current data
			$curr_channel = $channel;
			$curr_user = $user;
			$curr_operation = $operation;
		    
			# we got a hit! now to query his registered state (by whois)
			writeto($nid,"WHOIS $user");
		    }
		}
	}
}

sub on_raw
{
        my($self, $network, $server, $nick, $ident, $host, $cmd, @plist) = @_;
	# On freenode:
	# param: 320 <user> :is identified to services
	#
	# On unreal and inspircd:
	# param: 307 <user> :is a registered nick
	#
	# WARNING: Do not use 320 on anywhere but freenode without checking the
	# plist[2]!!! You can cause 320 to be placed in your whois on inspircd and
	# unreal and many others by connecting over ssl or setting an SWHOIS, which
	# means people could spoof identifying!
	#
	if ((($cmd eq "307" && ($plist[2] =~ /registered/i)) || ($cmd eq "320" && ($plist[2] =~ /is identified to services/))) && $plist[1] eq $curr_user)
	{
	    # do operation
	    main::add_mode_queue($network,$curr_channel,$curr_operation,$curr_user);	    
	    
	    # we recognized him/her - login please
	    auto_login($network,$curr_user);
	}
}

sub auto_login {
    my ($nid,$nick) = @_;
    
    my $nref  = "$nid,$nick";
    my $found_nick = $nick;
    
    if (defined $main::nicks{$nref}{login})
    {
        return; # "You are already logged in as $nicks{$nref}{login}.";
    }
    else 
    {
        $main::nicks{$nref}{login} = $found_nick;

        my @clist = main::get_chanlist($nid,$nick);
	
        foreach my $channel (@clist) 
	{
            $main::nicks{$nref}{lc($channel)}{flags}  = $main::users{$found_nick}{FLAGS}{$nid}{lc($channel)};
            $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{_}{_};
            $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{_}{lc($channel)};
            $main::nicks{$nref}{lc($channel)}{flags} .= $main::users{$found_nick}{FLAGS}{$nid}{_};
            $main::nicks{$nref}{lc($channel)}{flags}  = main::trim($main::nicks{$nref}{lc($channel)}{flags});
        }
    }
}																												

sub matcheshostandnick {
        my ($ident,$h,$nick) = @_;
        my $host = "$ident\@$h";
        foreach my $handle (keys %main::users) {
                next if $handle ne $nick;

                my $hostlist = main::trim($main::users{$handle}{HOST});
                my @hosts = split(' ',$hostlist);
                foreach my $chost (@hosts) {
                        if ($chost =~ /^\*/) {
                                $chost = main::wildcard_to_regexp($chost);
                        }
                        if ($host =~ /$chost/i) {
                                return $handle;
                        }
                }
        }
        return "";

}

sub handle_addauto {
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
        if (!main::hasflag($main::nicks{$nref}{login},"master",$network,$channel)) {
                return ("You do not have the master flag on \002$network/$channel\002");
        }
	my $username = shift @params;
	my $operation = shift @params;
        my $reason = join(' ',@params);
        $auto{"$network,$channel,$username,$operation"} = $reason;
        main::store_item($self,"$network,$channel,$username,$operation",$reason);
        return ("Added automatic operation \002$operation\002 onto \002$username\002 to \002$network/$channel\002 ($reason)");
}

sub handle_delauto {
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
        if (!main::hasflag($main::nicks{$nref}{login},"master",$network,$channel)) {
                return ("You do not have the master flag on \002$network/$channel\002");
        }
	my $username = shift @params;
	my $operation = shift @params;
        delete $auto{"$network,$channel,$username,$operation"};
        main::remove_item($self,"$network,$channel,$username,$operation");
        return ("Deleted automatic operation \002$operation\002 onto \002$username\002 from \002$network/$channel\002");
}

sub handle_listauto {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        if (!main::hasflag($main::nicks{$nref}{login},"owner",$network,$channel)) {
		return ("You must have owner status for this command!");
        }
	my @return = ();
        my $header = "\002".sprintf("%-10s","NETWORK").sprintf("%-15s","CHANNEL").sprintf("%-20s","USERNAME").sprintf("%-5s","OPERATION").sprintf("%-40s","REASON");
        push @return, $header;
        foreach my $key (keys %auto) {
		my ($network,$channel,$username,$operation) = split(',',$key,4);
                push @return, sprintf("%-10s",$network).sprintf("%-15s",$channel).sprintf("%-20s",$username).sprintf("%-5s",$operation).sprintf("%-40s",$auto{$key});
        }
        return @return;
}

1;
