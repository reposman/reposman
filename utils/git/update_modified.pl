#!/usr/bin/perl -w
use strict;
use Cwd qw/getcwd/;
use File::Spec;
use File::Glob qw/bsd_glob/;

my $TEST;
if(@ARGV and $ARGV[0] eq '--test') {
	$TEST = 1;
	shift;
}


sub run {
	print STDERR ":",join(" ",@_),"\n";
	if(!$TEST) {
		return system(@_) == 0
	}
	return;
}

sub auto_commit {
	my $dir = shift;
	my $scriptdir = shift;
	print STDERR "$dir not exist.\n" unless(-d $dir);
	chdir($dir) or die("$!\n");
	print STDERR "[$dir] commiting...\n";
	run('git','add','-A');
	run('sh',File::Spec->catfile($scriptdir, 's_commit.sh'));
}

my $cwd = getcwd();
my $scriptdir = File::Spec->rel2abs($0,$cwd);#;#ARGV[0];
(undef,$scriptdir,undef) = File::Spec->splitpath($scriptdir);
chdir($scriptdir) or die("$!\n");
$cwd = $scriptdir;

my @glob1 = qw{
	*.git/index
	*.git/refs/heads/*
	*.git/HEAD
	*/*.git/index
	*/*.git/refs/heads/*
	*/*.git/HEAD
};
my @glob2 = qw{
	*/git/index
	*/git/refs/heads/*
	*/git/HEAD
	*/*/git/index
	*/*/git/refs/heads/*
	*/*/git/HEAD
};
my @glob3 = qw{
	*/.git/index
	*/.git/refs/heads/*
	*/.git/HEAD
	*/*/.git/index
	*/*/.git/refs/heads/*
	*/*/.git/HEAD
};

my @list_cmd = qw/is-modified.pl/;
push @list_cmd,'--write' unless($TEST);
my @testing = map {glob($_)} (@glob1,@glob2,@glob3);
if(!@testing) {
	print STDERR "Nothing to do!\n";
	exit 0;
}
open FI,'-|',@list_cmd,@testing or die("$!\n");
my %modified;
while(<FI>) {
	chomp;
	s/([\/\.]git)\/.*$/$1/;
	$modified{$_} = 1;
}
close FI;

my %repos = %modified;
foreach(keys %modified) {
	next unless($_);
	if(m/^(.+)\/git$/) {
		if(-d "$1/.git") {
			$repos{"$1/.git"} = 1;
			auto_commit($1,$scriptdir);
			chdir($cwd);
		}
	}
}
print "[$_] haved been modified.\n" foreach(keys %repos);
foreach(keys %repos) {
	if(-f "$_/.reposman") {
		chdir($_);
		print STDERR "[$_] ";
		run('reposman','push',@ARGV);
		chdir($cwd);
	}
	elsif(m/^.*?([^\/]+)\/git$/) {
		run('reposman','push',@ARGV,'--',$1);
	}
	elsif(m/^(.+)\/\.git/) {
		if(-f "$1/.reposman") {
			chdir($1);
			print STDERR "[$1]";
			run('reposman','push',@ARGV);
			chdir($cwd);
		}
		else {
			run('reposman','push',@ARGV,'--',$1);
		}
	}
	elsif(m/^(.+)\.git$/) {
		run('reposman','push',@ARGV,'--',$1);
	}
	else {
		run('reposman','push',@ARGV,'--',$_);
	}
}
#run('sh',"$scriptdir/sync-repos.sh",keys %repos,@ARGV) unless($TEST);
run('git','add','.is-modified');
print STDERR "Done.\n";
#use Data::Dumper;print Data::Dumper->Dump([\%status,\%repos],[qw/*status *repos/]);

