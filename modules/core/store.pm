# Please include this text with any bug reports
# $Id: store.pm 1817 2005-09-19 15:06:38Z brain $
# =============================================

use strict;

sub init {
        die("This module may not be loaded from the configuration file");
}

my %store;

sub get_item {
	my ($module,$key) = @_;
	if (!defined $store{"$module $key"}) {
		return "";
	} else {
		return $store{"$module $key"};
	}
}

sub get_all_items {
	my ($module) = @_;
	my %return = ();
	foreach my $item (keys %store) {
		my ($mod,$key) = split(' ',$item);
		if ($module eq $mod) {
			$return{$key} = $store{$item};
		}
	}
	return %return;
}

sub store_item {
	my ($module,$key,$value) = @_;
	$store{"$module $key"} = $value;
}

sub remove_item {
	my ($module,$key) = @_;
	delete $store{"$module $key"};
}

sub loadstorefile {
	my ($name) = @_;
	my $fail = 0;
	my $line = "";
	open (FH, "<$name") or $fail = 1;
	if (!$fail) {
		while (chomp($line = <FH>)) {
			my ($module,$key,$value) = split(' ',$line,3);
			$store{"$module $key"} = $value;
		}
		close(FH);
	}
}

sub savestorefile {
	my ($name) = @_;
	my $fail = 0;
	open (FH, ">$name") or $fail = 1;
	if (!$fail) {
		foreach my $item (keys %store) {
			print FH "$item $store{$item}\n";
		}
		close(FH);
	}
}

1;
