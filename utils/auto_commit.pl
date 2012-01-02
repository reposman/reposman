#!/usr/bin/perl -w
use strict;
use Cwd qw/getcwd/;
use File::Spec;
my @subrepos = ('svn','git' );#,'git/privepo');
my $sub_script = 'update_modified.pl';
my $commit_script = 'commit.pl';
my @pargs;
my @cargs;
while(@ARGV) {
	$_ = shift @ARGV;
	if(m/(?:--master|--force|--mirror|--tags)/) {
		push @pargs,$_;
	}
	elsif($_ eq '--append') {
		my $what = shift(@ARGV);
		push @pargs,$_,$what;
	}
	else {
		push @cargs,$_;
	}
}

sub run {
	print STDERR "\t",join(" ",@_),"\n";
	return system(@_) == 0;
}
sub update_subrepo {
	my $dir = shift;
	my $scriptdir = shift;
	if(! -d $dir) {
		print STDERR "$dir not exist.\n";
		return;
	}
	chdir($dir) or die("$!\n");
	my $script;
	foreach('scripts/' . $sub_script, $sub_script) {
		if(-f $_) {
			$script = $_;
			last
		}
	}
	if(!$script) {
		print STDERR "Error: no update_mofidied.pl found.\n";
		return;
	}
	run('perl',$script,@_);
}
my $cwd = getcwd();
my $scriptdir = File::Spec->rel2abs($0,$cwd);#;#ARGV[0];
(undef,$scriptdir,undef) = File::Spec->splitpath($scriptdir);
foreach(@subrepos) {
	print STDERR "Updating [$_] ...\n";
	update_subrepo($_,$scriptdir,@pargs);
	chdir($cwd);
}
print STDERR "Commiting ...\n";
run('perl',File::Spec->catfile($scriptdir,$commit_script),@cargs);

