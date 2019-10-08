# Please include this text with any bug reports
# $Id: status.pm 1877 2005-09-22 22:20:01Z brain $
# =============================================

use strict;

require 'modules/core/irc.pm';

sub init {
        die("This module may not be loaded from the configuration file");
}

# returns 1 if the nick is opped on the given channel/network
# undef or 0 (should not differentiate between the two) if no status.

sub has_ops ($$$) {
	my ($network,$nick,$channel) = @_;
	my $tuple = "$network,$nick";
	return $main::nicks{$tuple}{lc($channel)}{has_ops};
}

# returns 1 if the nick is voiced on the given channel/network
# undef or 0 (should not differentiate between the two) if no status.

sub has_voice ($$$) {
        my ($network,$nick,$channel) = @_;
        my $tuple = "$network,$nick";
        return $main::nicks{$tuple}{lc($channel)}{has_voice};
}

# returns 1 if the nick is halfopped on the given channel/network
# undef or 0 (should not differentiate between the two) if no status.

sub has_halfops ($$$) {
        my ($network,$nick,$channel) = @_;
        my $tuple = "$network,$nick";
        return $main::nicks{$tuple}{lc($channel)}{has_halfops};
}

# returns 1 if the nick is founder on the given channel/network
# undef or 0 (should not differentiate between the two) if no status.

sub has_founder ($$$) {
        my ($network,$nick,$channel) = @_;
        my $tuple = "$network,$nick";
        return $main::nicks{$tuple}{lc($channel)}{has_founder};
}

# returns 1 if the nick is protected on the given channel/network
# undef or 0 (should not differentiate between the two) if no status.

sub has_protect ($$$) {
        my ($network,$nick,$channel) = @_;
        my $tuple = "$network,$nick";
        return $main::nicks{$tuple}{lc($channel)}{has_protect};
}

# Returns a list of channels for a given nick/network tuple

sub get_chanlist ($$) {
	my ($network,$nick) = @_;
	my $tuple = "$network,$nick";
	return split(' ',trim($main::nicks{$tuple}{channels}));
}

# Returns a list of nicks upon a certain channel/network tuple

sub get_members ($$) {
	my ($network,$channel) = @_;
	my @list = ();
	foreach my $id (keys %main::nicks) {
		if (($main::nicks{$id}{network} eq $network) && (is_on_channel($main::nicks{$id}{nick},$network,$channel))) {
			push @list,$main::nicks{$id}{nick};
		}
	}
	return @list;
}

# Returns 1 if a nick is on a channel upon a given network, 0 if otherwise

sub is_on_channel ($$$) {
	my ($nick,$network,$channel) = @_;
	my $tuple = "$network,$nick";
	my @chanlist = split(' ',$main::nicks{$tuple}{channels});
	foreach my $chan (@chanlist) {
		if ((lc(trim($chan)) eq lc(trim($channel))) && (trim($chan) ne "")) {
			return 1;
		}
	}
	return 0;
}


1;
