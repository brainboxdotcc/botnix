use DBI;

die "Too few args.\n\timportseen.pl inputfile.fact DBI:DbType;dbname=foobar username password" unless (@ARGV >= 2);

my($inputfile, $dbiargs, $user, $pass) = @ARGV;
my $nick = "Importer";
my $db = undef;

open(IF, "<$inputfile") or die "Error opening inputfile: $!";

$db = DBI->connect($dbiargs, $user, $pass, {'AutoCommit' => 1});

#$db->do("BEGIN TRANSACTION") or die "DBI error: $db->errstr";

while(chomp($line = <IF>))
{
	my ($nick, $rest) = split(' => ', $line, 2);
	my ($when, $where, $data) = split('', $rest, 3);
	print "$nick, $when, $where, '$data'\n";
	my $insertrow = $db->prepare("REPLACE INTO seen (ss_nick,ss_ident,ss_host,ss_network,ss_action,ss_when,ss_where,ss_data,ss_visible) VALUES (".$db->quote($nick).",'unknown','unknown','ChatSpike','MSG',".$db->quote($when).",".$db->quote($where).",".$db->quote($data).",'y')");
		$insertrow->execute() or die "DBI error: $db->errstr";
		$insertrow->finish();
	print "Duplicate record skipped\n" if ($@);
}

close(IF);
$db->disconnect();
