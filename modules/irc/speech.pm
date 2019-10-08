# Please include this text with any bug reports
# $Id: speech.pm 1850 2005-09-20 23:14:20Z brain $
# =============================================

package modules::irc::speech;
my $self = $me;

sub init {
	my ($me) = @_;
	$self = $me;

	main::add_help_commands("Channel Commands",("SAY","ACT"));
	main::add_context_help("SAY","Syntax: SAY <#channel> <text>\n        SAY <network> <#channel> <text>\nMake the bot message a channel.");
	main::add_context_help("ACT","Syntax: ACT <#channel> <text>\n        ACT <network> <#channel> <text>\nMake the bot message a channel with an action.");

	main::add_command("SAY",$self."::handle_say");
	main::add_command("ACT",$self."::handle_act");
}

sub implements {
        my @functions = ();
        return @functions;
}

sub shutdown {
	main::del_help_commands("Channel Commands",("SAY","ACT"));
	main::del_context_help("SAY");
	main::del_context_help("ACT");

	main::del_command("SAY");
	main::del_command("ACT");
}

sub handle_say {
	my ($nid,$nick,$ident,$host,@params) = @_;
	my $target = shift @params;
	my $channel,$network;
	# just a channel
	if ($target =~ /^(\#|\&)/) {
		$channel = $target;
		$network = $nid;
	} else {
		# a channel and a network
		$network = $target;
		$channel = shift @params;
	}
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
	my $text = join(' ',@params);
	main::send_privmsg($network,$channel,$text);
	return ("Said on $network/$channel: $text");
}

sub handle_act {
	my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
        my $channel,$network;
        # just a channel
        if ($target =~ /^(\#|\&)/) {
                $channel = $target;
                $network = $nid;
        } else {
                # a channel and a network
                $network = $target;
                $channel = shift @params;
        }
        my $nref = "$nid,$nick";
        if (!defined $main::nicks{$nref}{login}) {
                return ("You are not logged in!");
        }
        my $text = join(' ',@params);
        main::send_privmsg($network,$channel,"\001ACTION $text\001");
	return ("Said action on $network/$channel: $text");
}

1;
