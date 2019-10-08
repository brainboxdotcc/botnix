package modules::irc::karma;

my $self;
my %stats;
my %replies;
my $db;
my $quiet = 0;

sub init
{
	($self) = @_;
        ($_ eq 'modules::db::sql') and return foreach (@main::modules);
        main::lprint $self . ": Unable to obtain db object, do you have modules/db/sql.pm present and loaded?";
}

sub implements
{
	return ("on_privmsg", "on_configure", "after_configure");
}

sub shutdown { }

sub on_configure
{
	return 1;
}

sub after_configure
{
        $db  = &modules::db::sql::db;
}

sub on_privmsg
{
	my ($self, $nid, $server, $nick, $ident, $host, $target, $text) = @_;
	my $mynick = $main::netid{$nid}{nick};

	my %already = ();
	
	# User may karma multiple words in ONE line, but each seperate word may only be karma'd once per line.
	# e.g. "Brain++ Special--" is valid, but if the user types "Brain++ Brain++" only the first will count.
	my @words = split(" ", $text);
	foreach my $word (@words)
	{
		# cant karma when not on channel!
		last if ($target !~ /^#/);
			
		my $mod = 0;
		if ($word =~ /\-\-$/)
		{
			$mod = -1;
		}
		if ($word =~ /\+\+$/)
		{
			$mod = +1;
		}
		if ($word =~ /^\-\-/)
		{
			$mod = -1;
		}
		if ($word =~ /^\+\+/)
		{
			$mod = +1;
		}
		$word =~ s/\-\-//g;
		$word =~ s/\+\+//g;

		# Dont let the user karma themselves
		next if (lc($word) eq lc($nick));

		if ($mod != 0)
		{
			$modtext = $word;
			if (($modtext ne "") && ($already{$modtext} != 1))
			{
				$query = $db->prepare("SELECT karma FROM karma WHERE nick=".$db->quote($modtext));
				if ($query->execute())
				{
					my @result = $query->fetchrow_array();
					$query->finish();
					@result[0] += $mod;
					$db->do("REPLACE INTO karma (nick, karma, lastmodby) VALUES(".$db->quote($modtext).", ".@result[0].", ".$db->quote($nick).")");
					$already{$modtext} = 1;
				}
			}
		}
	}
	
	if ($text =~ /(karma|score|plusplus)\s+(\w+)$/i)
	{
		$modtext = $2;
		#main::send_privmsg($nid, $target, $reply) unless $quiet;
		$query = $db->prepare("SELECT karma FROM karma WHERE nick=".$db->quote($modtext));
		if ($query->execute())
		{
			my @result = $query->fetchrow_array();
			$query->finish();
			my $karma = @result[0];
			
			if (@result == undef || @result[0] == 0 || @result[0] eq "")
			{
				main::send_privmsg($nid, $target, "$modtext has neutral karma");
			}
			else
			{
				main::send_privmsg($nid, $target, "$modtext has a karma of " . $karma)
			}
		}
		else
		{
			main::send_privmsg($nid, $target, "$modtext has neutral karma");
		}
	}
}

1;
