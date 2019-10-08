# Please include this text with any bug reports
# $Id: null.pm 1804 2005-09-19 12:09:17Z brain $
# =============================================

package modules::log::null;

use strict;

sub init {
}

sub implements {
        my @functions = ("on_log", "on_log_directed");
        return @functions;
}

sub shutdown {
}

sub on_log {
}

sub on_log_directed {
}

1;
