#!/usr/bin/perl -w
use strict;
use Cwd qw/getcwd/;
use File::Spec;

my @GIT = qw/git/;
my @Files = qw{
	git-repos.log
	git-repos.log.old
	git-repos.log.diff
	*/.is-modified
};
my $cwd = getcwd();
my $scriptdir = File::Spec->rel2abs($0,$cwd);#;#ARGV[0];
(undef,$scriptdir,undef) = File::Spec->splitpath($scriptdir);

sub run {
	print STDERR "\t",join(" ",@_),"\n";
	return system(@_) == 0;
}
#print STDERR "Adding sub repos refs ...\n";
#run('sh',"$scriptdir/repos_add_refs.sh");
print STDERR "Generating logs ...\n";
run('perl',"$scriptdir/generate_log.pl");
foreach(@Files) {
	run(qw/git add/,$_);
}
print STDERR "Go commiting...\n";
run(qw/git commit/,@ARGV);
