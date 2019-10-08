# Please include this text with any bug reports
# $Id: ctcp.pm 7253 2007-06-08 14:19:44Z om $
# =============================================

package modules::irc::ctcp;

my %versions = ();
my %fingers = ();
my %answertime = ();
my %answerping = ();
my %answererror = ();

sub init {
}

sub implements {
        my @functions = ("before_configure","on_configure","on_privmsg","on_notice");
        return @functions;
}

sub shutdown {
}

sub before_configure {
	my ($self,$confname) = @_;
	%versions = ();
	%fingers = ();
	%answertime = ();
	%answerping = ();
	%answererror = ();
}

sub on_configure {
	my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
	if ($configline =~ /^versionreply\s+"(.+)"$/i) {
		if ($net_context eq "_") {
			main::lprint("versionreply command outside of network context on $configfile:$linenumber");
			return 0;
		}
		$versions{"$net_context"} = "$1";
	} elsif ($configline =~ /^fingerreply\s+"(.+?)"$/i) {
		if ($net_context eq "_") {
			main::lprint("fingerreply command outside of network context on $configfile:$linenumber");
			return 0;
		}
		$fingers{"$net_context"} = "$1";
	} elsif ($configline =~ /^ctcptime$/i) {
		if ($net_context eq "_") {
			main::lprint("ctcptime command outside of network context on $configfile:$linenumber");
			return 0;
		}
		$answertime{"$net_context"} = 1;
	} elsif ($configline =~ /^ctcperror$/i) {
		if ($net_context eq "_") {
			main::lprint("ctcperror command outside of network context on $configfile:$linenumber");
			return 0;
		}
		$answererror{"$net_context"} = 1;
	} elsif ($configline =~ /^ctcpping$/i) {
		if ($net_context eq "_") {
			main::lprint("ctcpping command outside of network context on $configfile:$linenumber");
			return 0;
		}
		$answerping{"$net_context"} = 1;
	}
	return 1;
}

sub on_privmsg {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if ($text =~ /^\001/) {
		$text =~ s/\001//g;
		if ($text =~ /^VERSION/i) {
			my $reply = "BotNix $VERSION";
			if (defined($versions{"$nid"})) {
				$reply = $versions{"$nid"};
			}
			main::send_notice($nid,$nick,"\001VERSION $reply\001");
		} elsif ($text =~ /^ACTION/i) {
			# do nothing with a CTCP ACTION (/ME)
		} elsif ($text =~ /^FINGER/i) {
			my $reply = "OUCH!";
			if (defined($fingers{"$nid"})) {
				$reply = $fingers{"$nid"};
			}
			main::send_notice($nid,$nick,"\001FINGER $reply\001");
		} elsif (($text =~ /^PING\s+(\d+)$/i) && ($answerping{"$nid"} == 1)) {
			main::send_notice($nid,$nick,"\001PING $1\001");
		} elsif (($text =~ /^TIME/i) && ($answertime{"$nid"} == 1)) {
			my ($Second, $Minute, $Hour, $Day, $Month, $Year, $WeekDay, $DayOfYear, $IsDST) = localtime(time);
			my $RealMonth = $Month + 1;
			$Year += 1900;
			$asctime = sprintf("%02d:%02d:%02d %02d/%02d/%04d",$Hour,$Minute,$Second,$Day,$RealMonth,$Year);
			main::send_notice($nid,$nick,"\001TIME $asctime\001");
		} else {
			if ($answererror{"$nid"} == 1) {
				main::send_notice($nid,$nick,"\001ERRMSG Invalid CTCP request.\001");
			}
		}
	}
}

sub on_notice {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
}


1;
