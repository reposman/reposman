#!/usr/bin/perl -w
use strict;
use Cwd qw/getcwd/;

my $log_filename = 'repos.log';
my @repos_type = qw/svn hg git/;
my $CWD = getcwd();

sub generate_log {
	my $logfile = shift;
	my $dir = shift;
	return unless(-d $dir);
	return unless(-f $dir . '/generate_log.pl');
	open FO, ">", $logfile;
	chdir $dir;
	open FI,"-|","perl","generate_log.pl";
	print FO <FI>;
	close FO;
	chdir $CWD;
}

sub generate_diff {
	my $filename = shift;
	my $left = shift;
	my $right = shift;
	open FO,">",$filename;
	open FI,"-|","diff",$left,$right;
	foreach(<FI>) {
		print FO $_;
		print STDERR $_;
	}
	close FI;
	close FO;
}

foreach(@repos_type) {
	next unless(-d $_);
	my $filename = "$_-$log_filename";
	if(-f $filename) {
		unlink $filename . ".old" if(-f $filename . ".old");
		rename $filename, $filename . ".old";
	}
	generate_log($filename,$_);
	if(-f $filename . ".old") {
		generate_diff("$filename.diff",$filename , $filename . ".old");
	}
	else {
		system("cp","--",$filename,"$filename.diff");
	}
}

