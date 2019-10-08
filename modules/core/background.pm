# Please include this text with any bug reports
# $Id: background.pm 10459 2008-09-07 21:44:27Z brain $
# =============================================

use strict;

sub init {
	die("This module may not be loaded from the configuration file");
}

sub daemon {
	use POSIX qw(setsid);

	if (!$main::debug && !$main::nofork) {
		umask 077;
		open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
		open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
		defined(my $pid = fork)   or die "Can't fork: $!";
		exit if $pid;
		setsid                    or die "Can't start a new session: $!";
	}
	main::writepid();
}

sub win32daemon {
        eval "use win32;Win32::SetChildShowWindow(Win32::SW_HIDE);";
        if ($@) {
                print "No win32 module! Aborting!\n";
                exit;
        }
	if (!defined $main::dont_fork) {
		print("Forking 'perl $0 --win32' to the background...\n");
		exec("perl $0 --win32");
		exit;
	}
}

sub writepid {
	my $pidfile = $_[0];
        open(PIDFILE, ">$pidfile");
        print PIDFILE "$$";
        close(PIDFILE);
}

1;
