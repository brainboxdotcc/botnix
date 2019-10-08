# Please include this text with any bug reports
# $Id: floatinglimit.pm 1838 2005-09-20 11:37:39Z brain $
# =============================================

package modules::irc::logtail;

use HTML::Entities;
use Tail;

my @files;


sub init {
	my ($self) = @_;
	$repeat = "";
	$wikipubdate = "";

	my @logs = qw(/var/log/maillog /var/log/secure /var/log/messages /var/log/dmesg /var/log/mysqld.log);
	foreach (@logs)
	{
	    push(@files, File::Tail->new(name=>"$_", debug=>$debug));
	}

	main::create_timer("logtail_timer",$self,"check_logs", 3);
}

sub implements {
        my @functions = ("on_privmsg");
        return @functions;
}

sub shutdown {
	my ($self,$nid,$server,$nick,$ident,$host,$channel)= @_;
	main::delete_timer("check_logs");
}

sub on_privmsg {
	my ($self,$nid,$server,$nick,$ident,$host,$target,$text) = @_;

	return unless $target =~ /^#/;

	if ($text =~ /ACTION\s+(hits|attacks|slaps|molests|kicks|punches|thwaps|smacks|kills|chops|bashes)\s+PostBot/i)
	{
		main::send_privmsg("ChatSpike",$target,"\1ACTION chops off $nick\'s arms, shoves them in a blender, blends them an drinks the fluids. MMMMM, LAMER JUICE. :-)\1");
		return;
	}
}

sub check_logs
{
	eval
	{
	#	main::send_privmsg("ChatSpike", "#coding", "Lulztastic.");

		$nfound=File::Tail::select(undef,undef,undef,60,@files);
		if ($nfound)
		{
			foreach my $file (@files)
			{
				 while (!$file->predict)
				{
					my $sLine = $file->read;

					if ($file->{"input"} eq "/var/log/maillog")
					{
						if ($sLine =~ /\:\sstatistics\:\s/)
						{
							next;
						}
					}

					main::send_privmsg("ChatSpike", "#logs", "\2" . $file->{"input"} . "\2: ". $sLine);
				}
			}
		}
		else
		{
			my @ints;
			foreach(@files)
			{
				push(@ints,$file->interval);
			}
		}
	}

}

1;
