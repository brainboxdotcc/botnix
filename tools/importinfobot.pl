use strict;
use DBI;

die "Too few args.\n\timportinfobot.pl inputfile.fact DBI:DbType;dbname=foobar username password" unless (@ARGV >= 2);

my($inputfile, $dbiargs, $user, $pass) = @ARGV;
my $nick = "Importer";
my $db = undef;

open(IF, "<$inputfile") or die "Error opening inputfile: $!";

$db = DBI->connect($dbiargs, $user, $pass, {'AutoCommit' => 1});

#$db->do("BEGIN TRANSACTION") or die "DBI error: $db->errstr";

my $checkifexists = $db->prepare("SELECT key_word FROM infobot WHERE key_word = ?");
my $updaterow = $db->prepare("UPDATE infobot SET value = ?, word = 'is', setby = " . $db->quote($nick) . ", whenset = " . time . ", locked = 0 WHERE key_word 
= ?");
my $insertrow = $db->prepare("INSERT INTO infobot (key_word,value,word,setby,whenset,locked) VALUES (?,?,'is'," . $db->quote($nick) . "," . time . ",0)");

while(<IF>)
{
	/^(.*) => (.*)$/i;
	my $key = lc($1);
	my $value = $2;
	
	$value =~ s/\$who/<who>/g;

	if($checkifexists->execute($key))
	{
		if($checkifexists->fetchrow_array)
		{
			$updaterow->execute($value, $key) or die "DBI error: $db->errstr";
		}
		else
		{
			$insertrow->execute($key, $value) or die "DBI error: $db->errstr";
		}
	}
	else
	{
		die "DBI error: $db->errstr";
	}
}

#$db->do("END TRANSACTION") or die "DBI error: $db->errstr";

$checkifexists->finish();
$updaterow->finish();
$insertrow->finish();


close(IF);
$db->disconnect();
