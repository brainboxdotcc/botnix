# Please include this text with any bug reports
# $Id: relay.pm 1900 2005-10-04 19:34:40Z brentd $
# =============================================

package modules::irc::relay;

$norelaynicks = ();
$relaysets = ();
my ($SNet, $SChan, $DNet, $DChan);

sub init {
	my ($self) = @_;
        main::add_help_commands("Channel Commands",("LIST"));
        main::add_context_help("LIST","Syntax: LIST [relay block name]\nList the people in other relay destinations.");
        main::add_command("LIST",$self."::handle_list");
}

sub implements {
        my @functions = ("on_configure","on_privmsg","on_join","on_part","on_kick","on_nick","on_mode","on_quit");
        return @functions;
}

sub shutdown {
	my ($self) = @_;
	main::del_help_commands("Channel Commands",("LIST"));
        main::del_context_help("LIST");
        main::del_command("LIST");
}

sub before_configure
{
	$norelaynicks = ();
	$relaysets = ();
	$relayblock = ();
	my ($SNet, $SChan, $DNet, $DChan);
}

sub on_configure
{
        my ($self, $network, $channel, $confname, $count, $line) = @_;
        my ($inblock, $dline) = (0,0);

        while(my $line = main::config_getline($count))
        {
                #main::lprint('RELAY $line = ' . $line);
		if ($line =~ /^norelaynicks\s+"(.+?)"$/i) {
                	my @flags = split(',',$1);
                  	foreach my $flag (@flags) {
				push(@norelaynicks, $flag);
                        	#main::lprint "norelaynicks: @norelaynicks";
                 	}
		}
                if($line =~ /^relay "(.*?)" \{$/)
                {
                        $relayblock = $1;
                        #main::lprint("...matched ($relayblock)");
                        $relaysets{$relayblock} = {};
                        $inblock = 1;
                        $count++;
                }
                elsif($inblock)
                {
                        if($line eq '}')
                        {
                                #main::lprint("end of block");
                                $inblock = 0;
                                $relayblock = undef;
                                last;
                        }
                        else
                        {
                                $line =~ /^(\w+)\s+"(.*)"\s+"(.*)"$/i;
				if (lc($1) eq "sourceinfo") {
                                	#main::lprint "option: $1, value: $2, value: $3";
                                	$relaysets{$relayblock}->{$1}{'Net'} = $2;
                                	$relaysets{$relayblock}->{$1}{'Chan'} = lc($3);
					#main::lprint "relayset SNET: $relaysets{$relayblock}->{$1}{'Net'}";
					#main::lprint "relayset SCHAN: $relaysets{$relayblock}->{$1}{'Chan'}";
                                	$count++;
				}
				if (lc($1) eq "destinfo") {
                                	#main::lprint "option: $1, value: $2, value: $3";
                                	$relaysets{$relayblock}->{$1}{$dline}{'Net'} = $2;
                                	$relaysets{$relayblock}->{$1}{$dline}{'Chan'} = lc($3);
                                	$relaysets{$relayblock}->{$1}{'Total'} = $dline+1;
					#main::lprint "relayset DNET -$dline-: $relaysets{$relayblock}->{$1}{$dline}{'Net'}";
					#main::lprint "relayset DCHAN -$dline-: $relaysets{$relayblock}->{$1}{$dline}{'Chan'}";
                                	$count++;
					$dline++;
				}
                        }
                }
                else
                {
                        last;
                }
        }
        main::config_setcurrentline($count);
	return(1);
}

sub on_privmsg {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;
	my $donotrelay = 0;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    my $sent_text = "";
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
	      foreach my $flag (@norelaynicks) {
		 if ("$nick!$ident\@$host" =~ /$flag/i) {
			$donotrelay = 1;
		 }
	      }
	      if ($nick eq $main::netid{$nid}{nick}) {
	         $donotrelay = 1;
	      }
   	      if (($target =~ /^[#\&]/) && ($nid eq $SNet) && (lc($target) eq $SChan) && ($donotrelay == 0)) {
		 if ($text =~ /^\001ACTION\s/) {
		    my $atext = $text;
		    $atext =~ s/^\001ACTION\s//g;
		    $atext =~ s/\001$//g;
		    $sent_text = "$SNet: * $nick/$SChan $atext";
		 } else {
		    my $atext = $text;
		    $sent_text = "$SNet: <$nick/$SChan> $atext";
		 }
		 if (!($atext =~ /^[\!\001]/)) {
			handle_private_message($DNet,$DChan,$sent_text);
		 }
  	      }
	    }
	}
}

sub on_join {
	my ($self,$nid,$server,$nick,$ident,$host,$channel) = @_;
	my $donotrelay = 0;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
	      foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
			$donotrelay = 1;
		}
	      }
	    if ($nick eq $main::netid{$nid}{nick}) {
	       $donotrelay = 1;
	    }
   	    if (($channel =~ /^[#\&]/) && ($nid eq $SNet) && (lc($channel) eq $SChan) && ($donotrelay == 0)) {
		my $sent_text = "$nick [$ident\@$host] has joined <$SNet/$SChan>";
		handle_private_message($DNet,$DChan,$sent_text);
  	    }
    	}
	}
}

sub on_part {
	my ($self,$nid,$server,$nick,$ident,$host,$channel,$reason) = @_;
	my $donotrelay = 0;
	my $sent_text = "";
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
	    foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
			$donotrelay = 1;
		}
	    }
	    if ($nick eq $main::netid{$nid}{nick}) {
	       $donotrelay = 1;
	    }
   	    if (($channel =~ /^[#\&]/) && ($nid eq $SNet) && (lc($channel) eq $SChan) && ($donotrelay == 0)) {
		if ($reason) {
		    $sent_text = "$nick [$ident\@$host] has left <$SNet/$SChan> [$reason]";
		} else {
		    $sent_text = "$nick [$ident\@$host] has left <$SNet/$SChan>";
		}
		handle_private_message($DNet,$DChan,$sent_text);
  	    }
    	}
	}
}

sub on_kick {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$channel,$reason) = @_;
	my $donotrelay = 0;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
            foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
                        $donotrelay = 1;
                }
            }
            foreach my $flag (@norelaynicks) {
                if (lc($target) eq lc($flag)) {
                        $donotrelay = 1;
                }
            }
	    if ($nick eq $main::netid{$nid}{nick}) {
	       $donotrelay = 1;
	    }
   	    if (($channel =~ /^[#\&]/) && ($nid eq $SNet) && (lc($channel) eq $SChan) && ($donotrelay == 0)) {
		my $sent_text = "$target was kicked from <$SNet/$SChan> by $nick [$reason]";
		handle_private_message($DNet,$DChan,$sent_text);
  	    }
    	}
	}
}

sub on_nick {
	my ($self,$nid,$server,$nick,$ident,$host,$newnick) = @_;
	my $donotrelay = 0;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
            foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
                        $donotrelay = 1;
                }
            }
	    if ($nick eq $main::netid{$nid}{nick}) {
	       $donotrelay = 1;
	    }
	    my @chanlist = main::get_chanlist($SNet,$nick);
	    foreach my $chan (@chanlist) {
                if ($chan eq $SChan) {
			$channel = $SChan;
                }
            }
   	    if (($channel =~ /^[#\&]/) && ($nid eq $SNet) && (lc($channel) eq $SChan) && ($donotrelay == 0)) {
		my $sent_text = "<$SNet/$SChan> $nick is now know as $newnick";
		handle_private_message($DNet,$DChan,$sent_text);
  	    }
    	}
	}
}

sub on_mode {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$modelist,@modeparams) = @_;
	my $donotrelay = 0;
	my $targ_string;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
              foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
                        $donotrelay = 1;
                }
              }
	      if ($nick eq $main::netid{$nid}{nick}) {
	         $donotrelay = 1;
	      }
	      my @chanlist = main::get_chanlist($SNet,$nick);
	      if (@modeparams ne "") {
		$targ_string = "@modeparams";
	      } else {
	  	$targ_string = $target;
	      }
   	      if (($target =~ /^[#\&]/) && ($nid eq $SNet) && (lc($target) eq $SChan) && ($donotrelay == 0)) {
	  	my $sent_text = "<$SNet/$SChan> $nick sets mode $modelist on $targ_string";
		handle_private_message($DNet,$DChan,$sent_text);
  	      }
	    }
    	}
}

sub on_quit {
	my ($self,$nid,$server,$nick,$ident,$host,$reason) = @_;
	my $donotrelay = 0;
	my $targ_string;
    	for my $k1 ( keys %relaysets ) {
            $SNet = $relaysets{$k1}->{'SourceInfo'}{'Net'};
            $SChan = $relaysets{$k1}->{'SourceInfo'}{'Chan'};
	    for (my $tmpval = 0; $tmpval < $relaysets{$k1}->{'DestInfo'}{'Total'}; $tmpval++) {
              $DNet = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Net'};
              $DChan = $relaysets{$k1}->{'DestInfo'}{$tmpval}{'Chan'};
            foreach my $flag (@norelaynicks) {
		if("$nick!$ident\@$host" =~ /$flag/i) {
                        $donotrelay = 1;
                }
            }
	    my @chanlist = main::get_chanlist($SNet,$nick);
	    foreach my $chan (@chanlist) {
                if (lc($chan) eq lc($SChan)) {
			$channel = $SChan;
                }
            }
	    if ($nick eq $main::netid{$nid}{nick}) {
	       $donotrelay = 1;
	    }
   	    if (($channel =~ /^[#\&]/) && ($nid eq $SNet) && (lc($channel) eq $SChan) && ($donotrelay == 0)) {
		my $sent_text = "<$SNet/$SChan> $nick [$ident\@$host] has quit [$reason]";
		handle_private_message($DNet,$DChan,$sent_text);
  	    }
    	}
	}
}

sub handle_private_message {
        my ($destnet,$destchan,$text) = @_;
	main::send_privmsg($destnet,$destchan,$text);
}

sub handle_list {
        my ($nid,$nick,$ident,$host,@params) = @_;
        my $target = shift @params;
	my $blocks = "Relay blocks: ";
	my @chanusers = ("Channel Users: ");
	my $counter = 0;
        if ($target) {
	   # list a block
	   for (my $tmpval = 0; $tmpval < $relaysets{$target}->{'DestInfo'}{'Total'}; $tmpval++) {
             my $DNet = $relaysets{$target}->{'DestInfo'}{$tmpval}{'Net'};
             my $DChan = $relaysets{$target}->{'DestInfo'}{$tmpval}{'Chan'};
	     #main::lprint "looking at target: $relaysets{$target}->{'DestInfo'}{$tmpval}{'Net'}\n";
	     #main::lprint "looking at target: $relaysets{$target}->{'DestInfo'}{$tmpval}{'Chan'}\n";
	     my $clist_raw = "";
	     @list = main::get_members($DNet,$DChan);
	     if (length(@list) > 500) { my $docheck = 1; }
	     foreach( @list ) {
	       if (main::has_ops($DNet,$_,$DChan)) {
	          $clist_raw = "$clist_raw\@$_ ";
	       } elsif (main::has_halfops($DNet,$_,$DChan)) {
	          $clist_raw = "$clist_raw\%$_ ";
		  #main::lprint"in halfops\n";
	       } elsif (main::has_voice($DNet,$_,$DChan)) {
	          $clist_raw = "$clist_raw\+$_ ";
	       } else {
	          $clist_raw = "$clist_raw$_ ";
	       }
	       $counter++;
	       if (($counter > 200) && $docheck) {
	          $clist_raw = "";
	          $counter = 0;
	          push(@chanusers,$clist_raw);
	       } 
	     }
	     $clist_raw =~ tr/\@\%\+/\001\002\003/;
	     @clist_sorted = sort(split(' ',$clist_raw));
	     $clist_raw = "<$DNet/$DChan> " . join(' ',@clist_sorted);
	     $clist_raw =~ tr/\001\002\003/\@\%\+/;
	     push(@chanusers,$clist_raw);
	   }
           return (@chanusers);
        } else {
		# list blocks
		for my $k1 ( keys %relaysets ) {
			$counter++;
			$blocks = "$blocks ($counter) $k1";
		}
        	return($blocks);
        }
}

1;
