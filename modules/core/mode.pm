# Please include this text with any bug reports
# $Id: mode.pm 1903 2005-10-05 13:07:16Z brain $
# =============================================

use strict;

sub init {
        die("This module may not be loaded from the configuration file");
}

my $direction = 1;

our %chanmodes = ();
our %usermodes = ();

my @modequeue = ();

our %cmodetable = (	"o" => \&m_op,
			"v" => \&m_voice,
			"h" => \&m_halfop,
			"a" => \&m_protect,
			"q" => \&m_founder,
			"b" => \&m_ban,
			"e" => \&m_except,
			"I" => \&m_invite,
			"p" => \&m_private,
			"s" => \&m_secret,
			"i" => \&m_invonly,
			"k" => \&m_key,
			"l" => \&m_limit,
			"n" => \&m_noexternal,
			"t" => \&m_optopic,
			"m" => \&m_moderate,
			"r" => \&m_registered,
			"+" => \&m_add,
			"-" => \&m_sub,
		);

our %umodetable = (
			"o" => \&um_oper,
			"s" => \&um_servernotice,
			"w" => \&um_wallops,
			"i" => \&um_invisible,
			"x" => \&um_cloak,
			"r" => \&um_registered,
			"+" => \&m_add,
			"-" => \&m_sub,
		);

sub add_mode_queue ($$$$) {
	my ($net,$target,$mode,$param) = @_;
	lprint("Add to mode queue on $net: $target $mode $param") if $main::debug;
	push @modequeue,"$net $target $mode $param";
}

sub flush_mode_queue () {
	my %cmodes = ();
	my %cparams = ();
	my %ccounts = ();
	return if scalar(@modequeue) < 1;
	lprint("Flush mode queue") if $main::debug;
	foreach my $item (@modequeue) {
		my ($net,$target,$mode,$param) = split(' ',$item,4);
		$cmodes{"$net,$target"} .= $mode;
		$cparams{"$net,$target"} .= "$param ";
		$ccounts{"$net,$target"}++;
		my $mm = 3;
		if (defined $main::maxmodes{$net}) { $mm = $main::maxmodes{$net} };
		if ($ccounts{"$net,$target"} >= $mm) {
			# we reach the overflow of 3 (on ircnet at least) for maximum number of modes per
			# line, so we should dump the queue and start again.
			writeto($net,"MODE $target ".$cmodes{"$net,$target"}." ".$cparams{"$net,$target"});
			delete $cmodes{"$net,$target"};
			delete $cparams{"$net,$target"};
			delete $ccounts{"$net,$target"};
		}
	}
	foreach my $t (keys %cmodes) {
		my ($net,$target) = split(',',$t,2);
		writeto($net,"MODE $target $cmodes{$t} $cparams{$t}");
	}
	@modequeue = ();
}

sub um_oper ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{oper} = $direction;
	return 0;
}

sub um_servernotice ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{servernotice} = $direction;
	return 0;
}

sub um_wallops ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{wallops} = $direction;
	return 0;
}

sub um_invisible ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{invisible} = $direction;
	return 0;
}

sub um_cloak ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{cloak} = $direction;
	return 0;
}

sub um_registered ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$usermodes{$nid}{registered} = $direction;
	return 0;
}

sub m_noexternal ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$chanmodes{$nid}{lc($target)}{noexternal} = $direction;
	return 0;
}

sub m_optopic ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$chanmodes{$nid}{lc($target)}{optopic} = $direction;
	return 0;
}

sub m_moderate ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        $chanmodes{$nid}{lc($target)}{moderated} = $direction;
        return 0;
}

sub m_key ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	if ($direction) {
		$chanmodes{$nid}{lc($target)}{key} = $param;
	} else {
		$chanmodes{$nid}{lc($target)}{key} = undef;
	}
	return 1;
}

sub m_limit ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	if ($direction) {
		$chanmodes{$nid}{lc($target)}{limit} = $param;
	} else {
		$chanmodes{$nid}{lc($target)}{limit} = 0;
	}
	# takes one parameter when adding, none when removing
	return $direction;
}

sub m_private ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$chanmodes{$nid}{lc($target)}{private} = $direction;
	return 0;
}

sub m_registered ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        $chanmodes{$nid}{lc($target)}{registered} = $direction;
        return 0;
}

sub m_secret ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$chanmodes{$nid}{lc($target)}{secret} = $direction;
	return 0;
}

sub m_invonly ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	$chanmodes{$nid}{lc($target)}{inviteonly} = $direction;
	return 0;
}

sub m_op ($$$$$$$) {
	my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
	my $key = "$nid,$param";
	$main::nicks{$key}{lc($target)}{has_ops} = $direction;
	return 1;
}

sub m_voice ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        my $key = "$nid,$param";
        $main::nicks{$key}{lc($target)}{has_voice} = $direction;
        return 1;
}

sub m_halfop ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        my $key = "$nid,$param";
        $main::nicks{$key}{lc($target)}{has_halfops} = $direction;
        return 1;
}

sub m_protect ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        my $key = "$nid,$param";
        $main::nicks{$key}{lc($target)}{has_protect} = $direction;
        return 1;
}

sub m_founder ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        my $key = "$nid,$param";
        $main::nicks{$key}{lc($target)}{has_founder} = $direction;
        return 1;
}

sub m_ban ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        return 1;
}

sub m_except ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        return 1;
}

sub m_invite ($$$$$$$) {
        my ($nid,$server,$nick,$ident,$host,$target,$param) = @_;
        return 1;
}

sub m_add ($$$$$$$) {
	$direction = 1;
	return 0;
}

sub m_sub ($$$$$$$) {
	$direction = 0;
	return 0;
}



sub mode ($$$$$$$@) {
	my ($nid,$server,$nick,$ident,$host,$target,$modelist,@modeparams) = @_;
	trigger_on_mode($nid,$server,$nick,$ident,$host,$target,$modelist,@modeparams);
	my $idx = 0;
	$direction = 1;
	lprint("Mode target: $target Mode list: $modelist Params: @modeparams") if $main::debug;

	# channel modes
	if ($target =~ /^(#|&)/) {
		foreach my $mode (split('',$modelist)) {
			trigger_on_single_mode($nid,$server,$nick,$ident,$host,$mode,$direction,$target,$modeparams[$idx]);
			if (defined $cmodetable{"$mode"}) {
				$idx += $cmodetable{"$mode"}($nid,$server,$nick,$ident,$host,$target,$modeparams[$idx]);
			} else {
				lprint("Unknown channel mode '$mode' with direction $direction") if $main::debug;
			}
		}
	} else {
		foreach my $mode (split('',$modelist)) {
			trigger_on_single_mode($nid,$server,$nick,$ident,$host,$mode,$direction,$target,$modeparams[$idx]);
			if (defined $umodetable{"$mode"}) {
				$idx += $umodetable{"$mode"}($nid,$server,$nick,$ident,$host,$target,$modeparams[$idx]);
			} else {
				lprint("Unknown user mode '$mode' with direction $direction") if $main::debug;
			}
		}
	}
}

1;
