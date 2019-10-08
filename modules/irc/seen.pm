use strict;

package modules::irc::seen;

my $db;

sub init
{
	my($self) = @_;

	main::add_help_commands("Channel Commands", ("SEEN"));
	main::add_context_help("SEEN", "Syntax: SEEN <nick>\n        SEEN <network> <nick>\nSearches for when the bot last saw the user with the specified nickname, optionally searching a specific network.\nIf no network is specified and the user cannot be found on the current network then other networks will be searched. If network is * then all networks will be searched.");
	main::add_context_help("SEENSEARCH", "Syntax: SEENSEARCH <network> <nick> <ident> <host>\nSearches for when the bot last saw any user(s) matching the parameters passed which should each be Perl regexps you may also specify any parameter as a * to match anything.\nIf network is * then all results will be returned from all networks, if network is _ (underscore) then only results from the current network will be used.\nThere should be fairly significant speed increases if you specify any of the parameters as a static word (\"^Foo\$\"), and a slight increase if you use \"*\" rather then a regexp doing the same.");

	main::add_command("SEEN", $self . "::handle_seen");
	main::add_command("SEENSEARCH", $self . "::handle_seensearch");
	
	($_ eq 'modules::db::sql') and return foreach (@main::modules);
	main::lprint $self . ": Unable to obtain db object, do you have modules/db/sql.pm present and loaded?";
	die;
}

sub implements
{
	my @functions = ("on_raw", "after_configure");
	return @functions;
}

sub shutdown
{
	main::del_help_commands("Channel Commands",("SEEN"));
	main::del_help_commands("Channel Commands",("SEENSEARCH"));
	main::del_context_help("SEEN");
	main::del_context_help("SEENSEARCH");

	main::del_command("SEEN");
	main::del_command("SEENSEARCH");
}

sub after_configure
{
	$db  = &modules::db::sql::db;
}

sub strago
{
	my($ago) = @_;
	my $secs = 1;
	my $mins = $secs*60;
	my $hours = $mins*60;
	my $days = $hours*24;
	my $weeks = $days*7;
	
	my @ints = ( $secs, $mins, $hours, $days, $weeks );

	my $ostr = "";

	for(my $pos = @ints-1; $pos >= 0; $pos--)
	{
		my $char = "";
		my $unitago = int $ago/@ints[$pos];
		$ago = $ago % @ints[$pos];

		if($unitago > 0 || @ints[$pos] == $secs)
		{
			if(@ints[$pos] == $weeks) { $char = "w"; }
			if(@ints[$pos] == $days) { $char = "d"; }
			if(@ints[$pos] == $hours) { $char = "h"; }
			if(@ints[$pos] == $mins) { $char = "m"; }
			if(@ints[$pos] == $secs) { $char = "s"; }
		
			$ostr .= ($unitago . $char . " ");
		}
	}
	chop $ostr;
	return $ostr;
}

sub on_raw
{
	my($self, $network, $server, $nick, $ident, $host, $cmd, @plist) = @_;
	my($data, $where) = "";
	my $visible = 'y';
	
	if(!$nick)
	{
		# We don't care about server messages here.
		return;
	}
		
	if($cmd eq "PRIVMSG" or $cmd eq "NOTICE")
	{
		$cmd = "MSG";
		$data = $plist[1];
		$where = $plist[0];
	}
	
	if($cmd eq "NOTICE")
	{
		$cmd = "NOT";
	}
	
	if(($cmd eq "QUIT") or ($cmd eq "NICK"))
	{
		$data = $plist[0];
	}
		
	if($cmd eq "JOIN")
	{
		$where = $plist[0];
	}
	
	if($where eq undef)
	{
		$where = "";
	}

	# main::lprint("nick: $nick, ident: $ident, host: $host, network: $network, command: $cmd, other params: @plist");	
	
	if($where =~ /^(\#|\&)/)
	{
		if($main::chanmodes{$network}{lc($where)}{secret})
		{
			$visible = 'n';
		}
	}
	
	my $query = $db->prepare("SELECT ss_nick FROM seen WHERE ss_nick = " . $db->quote($nick) ." AND ss_network = " . $db->quote($network));
	$query->execute();

	my $qstat;
	
	if($query->fetch) 
	{
		$qstat = $db->do("UPDATE seen SET ss_nick = ?, ss_ident = ?, ss_host = ?, ss_network = ?, ss_action = ?, ss_when = ?, ss_where = ?, ss_data = ?, ss_visible = ? WHERE ss_nick = ? AND ss_network = ?", undef, $nick, $ident, $host, $network, $cmd, time, $where, $data, $visible, $nick, $network)
	}
	else
	{
		$qstat = $db->do("INSERT INTO seen (ss_nick, ss_ident, ss_host, ss_network, ss_action, ss_when, ss_where, ss_data, ss_visible) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", undef, $nick, $ident, $host, $network, $cmd, time, $where, $data, $visible);
	}
	
	if(!$qstat)
	{
		# Handle errors.
		main::lprint "seen.pm, database error: " . $db->errstr;
		return;
	}

	$query->finish();
}

sub handle_seen
{
	my($network, $nick, $ident, $host, @params) = @_;
	my $target = shift @params;
	my @result;
	
	if(!($target =~ /^[a-zA-Z\[\]\{\}\\\|\^`_]{1}[a-zA-Z0-9\[\]\{\}\\\|\^`\-_]*$/))
	{
		return ("Invalid target ('$target')");
	}
	
	if(lc($target) eq lc($nick))
	{
		return ("How're the other personalities doing $nick?");
	}
	
	if(lc($target) eq lc($main::netid{$network}{nick}))
	{
		return ("...");
	}
		
	my $query = $db->prepare("SELECT * FROM seen WHERE ss_nick = " . $db->quote($target) . " AND ss_network = " . $db->quote($network) . " LIMIT 1") or return("Database error: " . $db->errstr);
	
	$query->execute() or return("Database error: " . $db->errstr);

	if(my $row = $query->fetchrow_hashref())
	{
		push @result, userow($nick, $row);
	}
	else
	{
		my $secondtry = $db->prepare("SELECT * FROM seen WHERE ss_nick = " . $db->quote($target) . " ORDER BY RAND() LIMIT 2") or return($db->errstr);
		$secondtry->execute() or return("Database error: " . $db->errstr);

		if($secondtry->rows > 0)
		{
			push @result, "Sorry $nick, I can't find any record of $target on $network, here's a couple of other places I've seen $target elsewhere:";
			while(my $row = $secondtry->fetchrow_hashref())
			{
				push @result, userow($nick, $row);
			}
		}
		else
		{
			push @result, "Sorry $nick, I can't find any record of $target";
		}
		
		$secondtry->finish();
	}
	
	$query->finish();
	
	return @result;
}

sub handle_seensearch
{
	my($network, $nick, $ident, $host, $snetwork, $snick, $sident, $shost, @params) = @_;
	
	my $nref = $network . "," . $nick;
	
	if(!defined $main::nicks{$nref}{login})
	{
		return ("You are not logged in!");
	}
	
	if(!main::hasflag($main::nicks{$nref}{login},"owner", $network, ''))
	{
		return ("You need to be an owner for this command!");
	}
	
	my %wheres = ();
	
	if(($snetwork == '_') || ($snetwork == $network))
	{
		# If the network is the current one.
		$wheres{'ss_network'} = $network;
		$snetwork = "*";
	}
	
	if($snick =~ /\^(\w+)\$/i)
	{
		$wheres{'ss_nick'} = $1;
	}
	
	if($sident =~ /\^(\w+)\$/i)
	{
		$wheres{'ss_ident'} = $1;
	}
	
	if($shost =~ /\^(\w+)\$/i)
	{
		$wheres{'ss_host'} = $1;
	}
	
	my $query = "SELECT * FROM seen";
	my $dfw = 0;
	
	while(my($field, $value) = each(%wheres))
	{
		if($dfw)
		{
			$query .= " AND $field = " . $db->quote($value);
		}
		else
		{
			$query .= " WHERE $field = " . $db->quote($value);
			$dfw = 1;
		}
	}
	
	$query .= " LIMIT 30";
	
	my $query = $db->prepare($query);
	my @results;
	$query->execute();
	
	if($query->rows)
	{
		while(my $row = $query->fetchrow_hashref())
		{
			# I could combine all these into one if()...but I think it looks more readable this way.
			if(($snetwork eq '*') or ($row->{'ss_network'} =~ qr/$snetwork/))
			{
				if(($snick eq '*') or ($row->{'ss_nick'} =~ qr/$snick/))
				{
					if(($sident eq '*') or ($row->{'ss_ident'} =~ qr/$sident/))
					{
						if(($shost eq '*') or ($row->{'ss_host'} =~ qr/$shost/))
						{
							push @results, userow($nick, $row);
						}							
					}
				}
			}
		}
	}

	$query->finish();
	
	if(@results)
	{
		return @results;
	}
	else
	{
		return ("No results");
	}
}

sub userow
{
	my($nick, $row) = @_;
	
	my $ago = time - $row->{'ss_when'};
	my $time = gmtime($row->{'ss_when'});
	my $desc = undef;
	if(($row->{'ss_action'} eq "MSG") or ($row->{'ss_action'} eq "NOT"))
	{
		if($row->{'ss_where'} =~ /^(\#|\&)/)
		{
			if($row->{'ss_visible'} eq 'y')
			{
				my $saying = (length $row->{'ss_data'} > 20) ? (substr($row->{'ss_data'}, 0, 20) . "...") : $row->{'ss_data'};
				$desc = "saying \"$saying\" on " . $row->{'ss_where'};
			}
			else
			{
				$desc = "active";
			}
		}
		else
		{
			# It was a private message or notice.
			$desc = "in a private chat";
		}
	}
	if($row->{'ss_action'} eq "QUIT") { $desc = "quitting IRC with the message \"" . $row->{'ss_data'} . "\""; }
	if($row->{'ss_action'} eq "NICK") { $desc = "changing nick to " . $row->{'ss_data'}; }
	if($row->{'ss_action'} eq "JOIN") { $desc = "joining a channel"; }
	if($row->{'ss_action'} eq "PART") { $desc = "leaving a channel"; }
	if($row->{'ss_action'} eq "KICK") { my($kicked, $msg) = split / :/, $row->{'ss_data'}; $desc = "kicking " . $kicked . " from a channel"; }			
	if($row->{'ss_action'} eq "MODE") { $desc = "setting mode(s) on a channel"; }
				
	return (sprintf('%s: %s (%s@%s) was last seen %s on %s on %s, that was %s ago', $nick, $row->{'ss_nick'}, $row->{'ss_ident'}, $row->{'ss_host'}, $desc, $row->{'ss_network'}, $time, strago($ago)));
}

1;
