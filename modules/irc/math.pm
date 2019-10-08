# This is ported from the Math.pm module
# written for the infobot by Kevin Lenzo.
# =======================================

package modules::irc::math;

my $self;
my %digits;

sub init
{
	$self = shift;
	%digits = (
		'first',	'1',
		'second',	'2',
		'third',	'3',
		'fourth',	'4',
		'fifth',	'5',
		'sixth',	'6',
		'seventh',	'7',
		'eighth',	'8',
		'ninth',	'9',
		'tenth',	'10',
		'one',		'1',
		'two',		'2',
		'three',	'3',
		'four',		'4',
		'five',		'5',
		'six',		'6',
		'seven',	'7',
		'eight',	'8',
		'nine',		'9',
		'ten',		'10',
	);
}

sub implements { return ("on_privmsg"); }

sub on_privmsg
{
	my ($self, $nid, $server, $nick, $ident, $host, $target, $text) = @_;
	my $mynick = $main::netid{$nid}{nick};

	# Module should only work
	# on in-channel text. :)
	return if ($target !~ /^#/);

	if (($text !~ /(\d+\.){2,}/) and ($text !~ /^\s*$/))
	{
		# Search and replace keys found in
		# the text from the %digits hash.
		foreach (keys %digits) { $text =~ s/$_/$digits{$_}/g; }

		while ($text =~ /(exp\s+([\w\d]+))/)
		{
			$exp = $1; 
			$val = exp($2); 
			$text =~ s/$exp/+$val/g;
		}   

		while ($text =~ /(hex2dec\s+([0-9A-Fa-f]+))/)
		{
			$exp = $1; 
			$val = hex($2);
			$text =~ s/$exp/+$val/g;
		}   

		while ($text =~ /^\s*(dec2hex\s+(\d+))\s*\?*/)
		{
			$exp = $1; 
			$val = sprintf("%x", "$2");
			$text =~ s/$exp/+$val/g;
		}   

		$e = exp(1);
		$text =~ s/\be\b/$e/;

		while ($text =~ /(log\s*((\d+\.?\d*)|\d*\.?\d+))\s*/)
		{
			$exp = $1; 
			$res = $2; 

			if ($res == 0) { $val = "Infinity";} 
			else { $val = log($res); } ; 

			$text =~ s/$exp/+$val/g;
		}   

		while ($text =~ /(bin2dec ([01]+))/)
		{
			$exp = $1; 
			$val = join ('', unpack ("B*", $2));
			$text =~ s/$exp/+$val/g;
		}   

		while ($text =~ /(dec2bin (\d+))/)
		{
			$exp = $1; 
			$val = join('', unpack('B*', pack('N', $2)));
			$val =~ s/^0+//;
			$text =~ s/$exp/+$val/g;
		}   

		$text =~ s/ to the / ** /g;
		$text =~ s/\btimes\b/\*/g;
		$text =~ s/\bdiv(ided by)? /\/ /g;
		$text =~ s/\bover /\/ /g;
		$text =~ s/\bsquared/\*\*2 /g;
		$text =~ s/\bcubed/\*\*3 /g;
		$text =~ s/\bto\s+(\d+)(r?st|nd|rd|th)?( power)?/\*\*$1 /ig;
		$text =~ s/\bpercent of/*0.01*/ig;
		$text =~ s/\bpercent/*0.01/ig;
		$text =~ s/\% of\b/*0.01*/g;
		$text =~ s/\%/*0.01/g;
		$text =~ s/\bsquare root of (\d+)/$1 ** 0.5 /ig;
		$text =~ s/\bcubed? root of (\d+)/$1 **(1.0\/3.0) /ig;
		$text =~ s/ of / * /;
		$text =~ s/(bit(-| )?)?xor(\'?e?d( with))?/\^/g;
		$text =~ s/(bit(-| )?)?or(\'?e?d( with))?/\|/g;
		$text =~ s/bit(-| )?and(\'?e?d( with))?/\& /g;
		$text =~ s/(plus|and)/+/ig;

		if
		(
			($text =~ /^\s*[-\d*+\s()\/^\.\|\&\*\!]+\s*$/) &&
			($text !~ /^\s*\(?\d+\.?\d*\)?\s*$/) &&
			($text !~ /^\s*$/) &&
			($text !~ /^\s*[( )]+\s*$/)
		)
		{
			$text = eval($text);

			if ($text =~ /^[-+\de\.]+$/)
			{
				$text =~ s/\.0+$//;
				$text =~ s/(\.\d+)000\d+/$1/;
				if (length($text) > 30) { $text = "A number with quite a few digits..."; }
				main::send_privmsg($nid, $target, $text);
			}
		}
	}
}

1;
