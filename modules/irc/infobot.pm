package modules::irc::infobot;

use strict;
use Data::Dumper::OneLine;
use constant { 'NOT_ADDRESSED' => 0, 'ADDRESSED_BY_NICKNAME' => 1, 'ADDRESSED_BY_NICKNAME_CORRECTION' => 2 };
# NOT_ADDRESSED => No Address (blah)
# ADDRESSED_BY_NICKNAME => Name Address (Botnick, blah)
# ADDRESSED_BY_NICKNAME_CORRECTION => Override Address (no Botnick, blah)

my $self;
my %stats;
my %replies;
my %sequence;
my $db;
my $quiet = 0;
my $lastresponse = "";
my $found = 0;
my $rn = "";

sub init
{
	($self) = @_;
	$stats{'startup'} = time;
	$stats{'modcount'} = 0;
	$stats{'qcount'} = 0;

        main::add_help_commands("Channel Commands",("DR"));
        main::add_context_help("DR","Syntax: DR <user> <text>\n.");

        main::add_command("DR",$self."::handle_dr");
	main::add_command("RN",$self."::handle_rn");

        main::lprint($self . ": Set up commands");

	($_ eq 'modules::db::sql') and return foreach (@main::modules);
	main::lprint($self . ": Unable to obtain db object, do you have modules/db/sql.pm present and loaded?");

}

sub implements
{
	return ("on_privmsg", "on_configure", "after_configure");
}

sub shutdown
{
	main::del_help_commands("Channel Commands",("DR"));
        main::del_context_help("DR");
        main::del_command("DR");
	main::del_command("RN");
}

sub on_configure
{
	my($modself, $net_context, $chan_context, $configfile, $linenumber, $configline) = @_;
	push(@{$replies{lc($1)}}, $2) if($configline =~ /^inf-(replies|dontknow|notnew|heard|confirm|loggedout|locked|forgot)\s+"(.+)"$/i);
	return 1;
}

sub after_configure
{
	$db  = &modules::db::sql::db;
}

sub handle_rn {
	my ($nid,$nick,$ident,$host,@params) = @_;
	$rn = join(' ', @params);
	return ("RN SET");
}

sub handle_dr {
	my ($nid,$nick,$ident,$host,@params) = @_;
	$found = 0;
	$lastresponse = "*NOTHING*";
	main::lprint($self . ": **** DR ****");
	my $who = shift @params;
	my $message = join(' ',@params);
	on_privmsg($self, "ChatSpike", "irc.chatspike.net", $who, $ident, $host, "Sporks", $message);
	$lastresponse = "$found $lastresponse";
	main::lprint("LAST RESPONSE: " . $lastresponse);
	$rn = "";
	return ($lastresponse,Dumper($main::netid{'ChatSpike'})); #encode_json($main::netid{"ChatSpike"}));
}

sub on_privmsg
{
	my($self, $nid, $server, $nick, $ident, $host, $target, $text) = @_;
	my $mynick = $main::netid{$nid}{nick};
	my($key, $value, $word, $when, $setby, $locked, $rpllist);
	my $level = NOT_ADDRESSED;
	$rpllist = "";

	$found = 1;

	my $direct_question = 0;
	$direct_question = 1 if ($text =~ /[\?!]$/);

	if (!defined($sequence{"$nid $nick"})) {
		$sequence{"$nid $nick"} = 0;
	}
	$sequence{"$nid $nick"}++;
		
	#if(($text =~ /^()(no\s*$mynick|$mynick)[?]*$/i) or ($text =~ /^(no\s*$mynick|$mynick|)[,: ]{0,}([^\001]+.*?[^\001]?)$/i))
	if($text =~ /^(no\s*$mynick[,: ]+|$mynick[,: ]+|)(.*?)$/i)
	{
		my $address = $1;
		$text = $2;

		# If it was addressing us, remove the part with our nick in it, and any punctuation after it...
		$level = ADDRESSED_BY_NICKNAME_CORRECTION() if($address =~ /^no\s*$mynick[,: ]+$/i);
		$level = ADDRESSED_BY_NICKNAME() if($address =~ /^$mynick[,: ]+$/i);

		if ($text =~ /^(who|what|where)\s+(is|was|are)\s+(.+?)[\?!\.]*$/i)
		{
			# This is a direct question, treat as addressed
			$text = $3 . "?";
			main::lprint("who|what|where is|was|are $text?") if $main::debug;
			$direct_question = 1;
		}
		
		# First option, someone is asking who told the bot something, simple enough...
		if($text =~ /^who told you about (.*?)\?*$/i)
		{
			# Set the key to the key itself without the whole "who told you..." string
			$key = $1;

			main::lprint("Who told me about...? '$key'") if $main::debug;
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;

			# And set which reply will be sent.
			my @rlist = get_def($key);
			
			$rpllist = @rlist > 0 ? 'heard' : 'dontknow';
			($value, $word, $setby, $when, $locked) = @rlist;

		 	main::lprint("rpllist: $rpllist") if $main::debug;
		}
		# Logged-in only lock command
		elsif(($level == ADDRESSED_BY_NICKNAME) and ($text =~ /^(lock|unlock|be quiet|be annoying)\s*(.*)$/i))
		{
			my $cmd = $1;
			$key = $2;
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;
			if(defined $main::nicks{"$nid,$nick"}{login})
			{
				if($cmd =~ /(lock|unlock)/i)
				{ 	
					if(($value, $word, $setby, $when, $locked) = get_def($key))
					{
						$locked = (lc $cmd eq 'lock') ? 1 : 0;
						set_def($key, $value, $word, $setby, $when, $locked);
						$found = 0;
						$rpllist = "confirm";
					}
					else
					{
						$found = 0;
						$rpllist = "dontknow";
					}
				}
				else
				{
					$quiet = ($cmd =~ /be quiet/i) ? 1 : 0;
				}
			}
			else
			{
				$rpllist = "loggedout";
			}
		}
		# Forget command...conratulations me on nearly releasing without this...
		elsif(($level == ADDRESSED_BY_NICKNAME) and ($text =~ /^forget (.*?)$/i))
		{
			$key = $1;
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;
			
			if(get_def($key))
			{
				if(locked($key))
				{
					$rpllist = 'locked';
					$found = 1;
				}
				else
				{
					set_def($key);
					$rpllist = 'forgot';
					$found = 1;
				}
			}
			else
			{
				$found = 0;
				$rpllist = "dontknow";
			}
		}
		# Status command, world availiable
		elsif($level >= ADDRESSED_BY_NICKNAME and $text =~ /^status\?*$/i)
		{
			main::lprint("*** infobot status report ***");
			# my($sec, $min, $hour, $mday, $mon, $year) = localtime(time-$stats{'startup'});
			# sprintf("%4d-%02d-%02d %02d:%02d:%02d ",$year+1900,$mon+1,$mday,$hour,$min,$sec)
			my $phrases = get_phrase_count();
			my ($days, $hours, $mins, $secs) = main::get_uptime();
			my $status = "Since " . gmtime($stats{'startup'}) . ", there have been " . $stats{'modcount'} . " modifications and " . $stats{'qcount'} . " questions. I have been alive for $days days, $hours hours, $mins mins, and $secs seconds, I currently know " . $phrases . " phrases of rubbish";
			$lastresponse = $status;
			main::send_privmsg($nid, $target, $status);
			return;
		}
		# Literal command, print out key and value with no parsing
		elsif ($text =~ /^literal (.*)\?*$/i)
		{
			$key = $1;
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;
			# This bit is a bit different, it bypasses a lot of the parsing for stuff like %n
			if(my($reply) = get_def($key))
			{
				$lastresponse = "$key is $reply";
				main::send_privmsg($nid, $target, "$key is $reply");
				return;
			}
			else
			{
				$found = 1;
				$rpllist = "dontknow";
			}
		}
		elsif ($text =~ /^\001/)
		{
			$text =~ s/\001//g;
			if ($text =~ /^ACTION (.+?)$/)
			{
				my $nkey = $1;
				if (get_def($nkey))
				{
					$text = $1;
				}

				else
				{
					main::lprint("Learning from action on $nick: was '$1'") if $main::debug;
					($key, $word, $value) = ($nick, "was", $1);
				
					$key =~ s/(\.|\,|\!|\?|\s+)$//g;
					return if ($key eq "");
				
					if(locked($key))
					{
						$rpllist = 'locked' if($level >= ADDRESSED_BY_NICKNAME());
					}
					elsif(($level eq ADDRESSED_BY_NICKNAME_CORRECTION()) or (!get_def($key)))
					{
						set_def($key, $value, $word, $nick, time, 0);
							$stats{'modcount'}++;
						$found = 0;
						$rpllist = 'confirm' if($level >= ADDRESSED_BY_NICKNAME());
					}
					else
					{
						my($reply) = get_def($key);
						if($reply ne $value)
						{
							$rpllist = 'notnew' if($level >= ADDRESSED_BY_NICKNAME());
						} 
					}
				}
			}
		}
		# Next option, someone is either adding a new phrase to the bot or editing an old one, a bit trickier...
		# Many more stop words than infobot!
		elsif (($text =~ /^(.*?)\s+=(is|are|was|arent|aren't|can|can't|cant|will|has|had|r|might|may)=\s+(.*)\s*$/i or $text =~ /^(.*?)\s+(is|are|was|arent|aren't|can|can't|cant|will|has|had|r|might|may)\s+(.*)\s*$/i) and ($rpllist eq ""))
		{
			($key, $word, $value) = ($1, $2, $3);

			# Strip trailing punctuation
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;
			return if ($key eq "");
		
			if(locked($key))
			{
				$rpllist = 'locked' if($level >= ADDRESSED_BY_NICKNAME());
			}
			elsif(($level eq ADDRESSED_BY_NICKNAME_CORRECTION()) or (!get_def($key)))
			{
				# If we're overriding, then just do it, and do it if it's not already set.
				set_def($key, $value, $word, $nick, time, 0);
				$stats{'modcount'}++;
			
				# Only send the confirmation message if the bot was addressed directly...cut down on spam
				$found = 0;
				$rpllist = 'confirm' if($level >= ADDRESSED_BY_NICKNAME());
			}
			else
			{
				my($reply) = get_def($key);

				if ($value =~ /^also\s+/i)
				{
					$value =~ s/^also\s+//i;
					if ($value =~ /^\|/)
					{
						$value = $reply . " " . $value;
					}
					else
					{
						$value = $reply . " or " . $value;
					}
					set_def($key, $value, $word, $nick, time, 0);
					$found = 0;
					$rpllist = 'confirm' if($level >= ADDRESSED_BY_NICKNAME());
				}
				elsif($reply ne $value)
				{
					# If someone tries to set something which is already set without overriding, tell them it's already set.
					$found = 1;
					$rpllist = 'notnew' if($level >= ADDRESSED_BY_NICKNAME());
				}
			}
		}
		
		# And the third option, someone is asking about a phrase
		if (($text =~ /^(.*?)\?*\s*$/i) && ($rpllist eq ""))
		{
			$key = $1;
			$stats{'qcount'}++;
			$key =~ s/(\.|\,|\!|\?|\s+)$//g;

			if(($value) = get_def($key))
			{
				if (($direct_question == 1) || (rand(15) > 13) || ($level >= ADDRESSED_BY_NICKNAME))
				{
					$rpllist = 'replies';
				}
			}
			elsif($level >= ADDRESSED_BY_NICKNAME)
			{
				# We were asked about something we didn't know about...
				# Don't say we don't know unless we were addressed directly
				$found = 0;
				$rpllist = 'dontknow';
			}
		}
		# End of line handling
	}
	
	if($rpllist)
	{
		my $repeat;
		my $reply = "";
		my $locked;

		($value, $word, $setby, $when, $locked) = get_def($key);
		$when = gmtime($when);

		main::lprint("Got def for $key: $value, $word, $setby") if $main::debug;

		do
		{
			$repeat = 0;
			$reply = $replies{$rpllist}[ int rand(@{$replies{$rpllist}}) ];
			if(!$reply)
			{
				$reply = "WARNING: No configured replies. Bad botmaster :(";
			}

			$value = expand(getreply($value), $when, $nick, $target, $nid);

			main::lprint("Value after expand: $value") if $main::debug;
		
			$reply =~ s/%k/$key/g;
			$reply =~ s/%w/$word/g;
			$reply =~ s/%n/$nick/g;
			$reply =~ s/%m/$mynick/g;
			$reply =~ s/%d/$when/g;
			$reply =~ s/%s/$setby/g;

			main::lprint("Replaced: $value") if $main::debug;
		
			if($locked and $locked eq 'lk')
			{
				$reply =~ s/%l/locked/g;
			}
			else
			{
				$reply =~ s/%l/unlocked/g;
			}

			# Gobble up empty reply
			return if (($value =~ /^<reply>$/i) and ($rpllist eq 'replies'));

			main::lprint("Not an empty reply, continuing") if $main::debug;

			if ($rpllist eq 'replies' and $value =~ /<alias>\s*(.*)/i)
			{
				my $oldkey = $key;
				$key = $1;
				main::lprint("Value is an alias: fetch $key") if $main::debug;
				my @arr = get_def($key);
				if (@arr == 0)
				{
					$lastresponse = "$oldkey was <alias>'ed to $key, but $key does not exist! :(";
					main::send_privmsg($nid, $target, "$oldkey was <alias>'ed to $key, but $key does not exist! :(");
					return;
				}
				($value, $word, $setby, $when, $locked) = @arr;
				$when = gmtime($when);
				main::lprint("Follow $key, got: $value, $word, $setby") if $main::debug;

				# Dont allow alias loops
				$repeat = 1 if ($value !~ /<alias>/i);
			}

		}
		while ($repeat != 0);

		main::lprint("Left fetch loop") if $main::debug;

		
		if($rpllist eq 'replies' and $value =~ /<(reply|action)>\s*(.*)/i)
		{
			main::lprint("Value is <reply> or <action>") if $main::debug;
			# Just a <reply>? bog off...
			return if ($value =~ /^\s*<reply>\s*$/i);

			main::lprint("Value not an empty reply") if $main::debug;

			# This bit is a bit different, it bypasses a lot of the parsing for stuff like %n
			$reply = (lc($1) eq 'reply') ? $2 : "\001ACTION " . $2 . "\001";

			main::lprint("Reply: $reply") if $main::debug;
			
			my $x = expand($reply, $when, $nick, $target, $nid);
			return if ($x eq '%v');

			main::lprint("Final PRIVMSG: $x") if $main::debug;
		
			$lastresponse = $x;	
			main::send_privmsg($nid, $target, $x);
			return;
		}

		main::lprint("Not a <reply> or <action>") if $main::debug;
		
		# %v is last, as it's the user input...and we don't want just anyone to be able to access the other %'es
		$reply =~ s/%v/$value/g;

		# Chomp nom nom nom
		return if ($reply eq '%v' || $reply eq '');

		main::lprint("Not reply or action, final PRIVMSG: $reply") if $main::debug;
	
		$lastresponse = $reply;
		main::send_privmsg($nid, $target, $reply) unless $quiet;
	}
}

sub get_def
{
	my($key) = @_;
	my $query;

	if(($query = $db->prepare("SELECT value,word,setby,whenset,locked FROM infobot WHERE key_word = ?")) and $query->execute(lc $key))
	{
		my @result = $query->fetchrow_array();
		$query->finish();
		return @result;
	}
	else
	{
		main::lprint("infobot.pm: Database error: " . $db->errstr);
		return ();
	}
}

sub get_phrase_count
{
	my $query;

	if(($query = $db->prepare("SELECT COUNT(*) FROM infobot")) and $query->execute())
	{
		my @result = $query->fetchrow_array();
		$query->finish();
		return $result[0];
	}
	else
	{
		main::lprint("infobot.pm: Database error: " . $db->errstr);
		return "an unknown number";
	}
}

sub set_def
{
	my($key,$value,$word,$setby,$when,$locked) = @_;
	my $qstat;

	$key = lc $key;
	
	if($value)
	{
		my $query = $db->prepare("SELECT key_word FROM infobot WHERE key_word = ?");
		$qstat = $query->execute($key);

		if($qstat)
		{
			if($query->fetchrow_array)
			{
				$qstat = $db->do("UPDATE infobot SET value = ?, word = ?, setby = ?, whenset = ?, locked = ? WHERE key_word = ?", {}, $value, 
$word, 
$setby, $when, $locked, $key);
			}
			else
			{
				$qstat = $db->do("INSERT INTO infobot (key_word,value,word,setby,whenset,locked) VALUES (?,?,?,?,?,?)", {}, $key, $value, $word, 
$setby, $when, $locked);
			}
		}

		$query->finish();
	}
	else
	{
		# No parameters were passed other than a key, this means remove the key.
		$qstat = $db->do("DELETE FROM infobot WHERE key_word = ?", {}, $key);
	}

	if(!$qstat)
	{
		# Handle errors.
		main::lprint("infobot.pm, database error: " . $db->errstr);
		return;
	}
}

sub expand
{
	# Expands all the tokens which can be used in the user input.
	my($str, $setdate, $nick, $target, $nid) = @_;
	my $mynick = $main::netid{$nid}{nick};
	my $randuser = $main::users[int rand @main::users];
	
	my @users = main::get_members $nid, $target;
	if ($rn ne "") {
		$randuser = $rn;
	}
	my $date = gmtime;

	my $sc = 0;
	if (defined($sequence{"$nid $nick"})) {
		$sc = $sequence{"$nid $nick"};
	}

	# Define the expansions which can be used in a value (the part it learnt, not the part you configured)
	$str =~ s/<me>/$mynick/gi; # Bot's nick
	$str =~ s/<who>/$nick/gi; # Person asking's nick
	$str =~ s/<random>/$randuser/gi; # Random person on the channel
	$str =~ s/<date>/$setdate/gi; # Date the phrase was learnt
	$str =~ s/<now>/$date/gi; # Current date
	$str =~ s/<sequence>/$sc/gi; # Sequence number

	# Randomised string lists
	while ($str =~ /<list:.+?>/) {
		my ($choicelist) = $str =~ m/<list:(.+?)>/;
		my @opts = split /,/, $choicelist;
		my $opt = @opts[int rand @opts];
		$str =~ s/<list:.+?>/$opt/;
	}

	# Blank things that couldnt be defined at all
	$str = "" if ($str eq '%v');

	return $str;
}

sub getreply
{
	# Split a reply string on | and return a random one.
	my($list) = @_;
	my @replies = split /\|/, $list;
	my $reply = $replies[int rand @replies];
	return $reply;
}

sub locked
{
	my($key) = @_;
	my(undef,undef,undef,undef,$locked) = get_def($key);
	return $locked if($locked);
	return 0;
}

1;
