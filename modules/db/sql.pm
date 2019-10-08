use strict;
use DBI;

package modules::db::sql;

my %databases; # Info read from config, db usernames, passwords, hosts etc.
my %connections; # The connection objects themselves.

sub init
{
	# Nothing to do here, but init() is required so...
}

sub implements
{
	return ("on_configure");
}

sub shutdown
{
	while(my($key, $value) = each(%connections))
	{
		$value->disconnect();
	}
}

sub on_configure
{
	my ($self, $network, $channel, $confname, $count, $line) = @_;
	my $inblock = 0;
	my $dbtitle;
	
	# Use this to provide a way of ordering the connections afterwards. We want the default to be the first one in the config file.
	
	while(my $line = main::config_getline($count))
	{
		# main::lprint('$line = ' . $line);
		if($line =~ /^db "(.*)" \{$/)
		{
			$dbtitle = $1;
			# main::lprint("...matched ($dbtitle)");
			$databases{$dbtitle} = {'id' => scalar keys %databases, 'engine' => 'mysql', 'host' => '', 'name' => '', 'user' => '', 'pass' => ''};
			$inblock = 1;
			$count++;
		}
		elsif($inblock)
		{		
			if($line =~ /^\s{0,}}\s{0,}$/)
			{
				# main::lprint("end of block");
				$inblock = 0;
				$dbtitle = undef;
				last;
			}
			else
			{
				$line =~ /^(\w+)\s+"(.*)"$/i;
				# main::lprint "option: $1, value: $2";
				$databases{$dbtitle}->{$1} = $2;
				$count++;
			}
		}
		else
		{
			last;
		}
	}
	
	main::config_setcurrentline($count);
	return 1; # Keep parsing...
}

sub db
{
	my($conninfo, $connname);
	
	if(@_ && defined($databases{$_[0]}))
	{
		$conninfo = $databases{$_[0]};
		$connname = $_[0];
	}
	else
	{
		while(($connname, $conninfo) = each(%databases))
		{
			if($conninfo->{'id'} eq 0)
			{
				# It's the first in the config file.
				last;
			}
		}
	}
	
	my $dbc;
	
	if(defined $connections{$connname})
	{
		$dbc = $connections{$connname};
	}
	else
	{
		main::lprint("Connecting to database '" . $conninfo->{'name'} . "' on host '" . $conninfo->{'host'} . "' user/pass: " . $conninfo->{'user'} . "/" . $conninfo>{'pass'}) if $main::debug;
		eval
		{
			if($conninfo->{'engine'} =~ /SQLite[2]?/)
			{
				$dbc = DBI->connect("DBI:" . $conninfo->{'engine'} . ":dbname=" . $conninfo->{'name'}, '', '', {'AutoCommit' => 1});
				$dbc->func('RAND', 0, sub { return "RANDOM()" }, 'create_function');
			}

			else
			{
				my $host = (length $conninfo->{'host'}) ? ";host=" . $conninfo->{'host'} : '';
				$dbc = DBI->connect("DBI:" . $conninfo->{'engine'} . ":database=" . $conninfo->{'name'} . $host, $conninfo->{'user'}, $conninfo->{'pass'}, {'AutoCommit' => 1});
			}
		};
		
		if($@)
		{
			main::lprint "Error loading database module and connecting. You probably specified (or didn't specify at all) an invalid DBD driver as the 'driver' option in the db{} config block. Error: $@";
		}
		else
		{
			# We don't want a br0ked connection in the connections list.
			$connections{$connname} = $dbc;
		}
	}
	
	# Reset the internal hash pointer
	keys %databases;
	
	return $dbc;
}

1;
