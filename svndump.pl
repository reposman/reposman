#!/usr/bin/env perl
use strict;
use Cwd qw/getcwd/;
my $cwd = getcwd;

foreach my $local (@ARGV) {
	my $name = $local;
	$name =~ s/\//_/g;
	$name =~ s/svn_|_svn//g;
	$local = "$cwd/$local" unless($local =~ m/^\//);
	print STDERR "$local ...\n";
	my $rev;
	my $last;
	if(open FI,"-|",'svn','info',"file://$local") {
		foreach(<FI>) {
			if(m/^\s*Last Changed Rev:\s*(\d+)/) {
				$rev = $1;
			}
			elsif(m/^\s*Last Changed Date:\s*(\d+)-(\d+)-(\d+)/) {
				$last = "$1$2$3";
			}
		}
		close FI;
		my $dst = $name;
		$dst = $dst . "_r$rev" if($rev);
		$dst = $dst . "_$last" if($last);
		open FI,"-|",'svnadmin','dump',$local;
		open FO,">","$dst.svndump";
		print FO <FI>;
		close FO;
		close FI;
		system("bzip2","-9","-v","$dst.svndump");
	}
	else {
		print STDERR "error: not a subversion repository\n";
	}
}
