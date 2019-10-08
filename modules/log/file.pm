# Please include this text with any bug reports
# $Id: file.pm 1836 2005-09-20 11:29:19Z brain $
# =============================================

package modules::log::file;

my %logfiles = ();
my %timestamps = ();

sub init {
}

sub implements {
        my @functions = ("before_configure","on_configure","on_log", "on_log_directed");
        return @functions;
}

sub shutdown {
}

sub do_timestamp {
	($sec, $min, $hour, $mday, $mon, $year, undef, undef, undef) = localtime(time);
	return sprintf("%4d-%02d-%02d %02d:%02d:%02d ",$year+1900,$mon+1,$mday,$hour,$min,$sec); 
}

sub on_log {
	my ($self,@text) = @_;
	my $fail = 0;
	open(FH,">>$logfiles{_}{_}") or $fail = 1;
	if (!$fail) {
		if ($timestamps{_}{_} == 1) {
			print FH do_timestamp;
		}
		print FH join(' ',@text) . "\n";
		close(FH);
	}
}

sub on_log_directed {
	my ($self,$command,$nick,$net,$channel,@text) = @_;
	my $fail = 0;
	my $log = "";
	if (defined $logfiles{$net}{$channel}) {
		$log = $logfiles{$net}{$channel};
	} else {
		$log = $logfiles{_}{_};
	}
	open(FH,">>$log") or $fail = 1;
	if (!$fail) {
		if (($timestamps{$net}{$channel} == 1) || ($timestamps{_}{$channel} == 1) || ($timestamps{_}{_} == 1) || ($timestamps{$net}{_} == 1)) {
			print FH do_timestamp;
		}
		print FH "<$net/$channel> $nick '$command' -> '" . join(' ',@text) . "'\n";
		close(FH);
	}
}

sub before_configure {
	my ($self,$confname) = @_;
	%logfiles = ();
	%timestamps = ();
}

sub on_configure {
	my ($self,$net_context,$chan_context,$configfile,$linenumber,$configline) = @_;
	if ($chan_context eq "") {
		$chan_context = "_";
	}
	if ($configline =~ /^logfile\s+"(.+)"$/i) {
		$logfiles{"$net_context"}{"$chan_context"} = $1;
	}
	if ($configline =~ /^timestamps\s+"(.+)"$/i) {
		my $val = "$1";
		$timestamps{$net_context}{$chan_context} = ($val =~ /^yes$/i);
	}
	return 1;
}

1;
