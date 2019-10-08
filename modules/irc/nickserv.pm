# Please include this text with any bug reports
# $Id: nickserv.pm 1894 2005-09-27 11:11:59Z brain $
# =============================================

package modules::irc::nickserv;

my %passes = ();

sub init {
	my ($self) = @_;
}

sub implements {
        my @functions = ("before_configure","on_configure", "on_raw","on_notice");
        return @functions;
}

sub shutdown {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
}

sub before_configure {
        my ($self,$confname) = @_;
	%passes = ();
}

sub identify ($) {
	my ($nid) = @_;
	if (defined $passes{$nid}) {
		main::writeto($nid,"NICKSERV IDENTIFY $passes{$nid}");
	} elsif (defined $passes{_}) {
		main::writeto($nid,"NICKSERV IDENTIFY $passes{$nid}");
	}
}

sub on_raw {
	my ($self,$nid,$server,$nick,$ident,$host,$command,@plist) = @_;
	if ($command == 376) {
		identify($nid);
	}
}

sub on_notice {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	if (($nick =~ /NickServ/i) && ($text =~ /nickname is registered/i)) {
		identify($nid);
	}
}

sub on_configure {
        my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
        if ($configline =~ /^nickservpass\s+"(.+)"$/i) {
                $passes{$net_context} = $1;
        }
	return 1;
}


1;
