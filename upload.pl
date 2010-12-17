#!/usr/bin/env perl
# $Id$
use strict;

if(!@ARGV) {
	print STDERR "Usage:$0 [options] files_to_upload...\n";
	exit 0;
}

my $PDIR=$0;
$PDIR =~ s/\/[^\/]+$//;
my @cmd=('python',"$PDIR/googlecode_upload.py",'-u','eotect','-p','vcsplace');

my @args = @ARGV;
@ARGV = ();
while(@args) {
	$_ = shift @args;
	if($_ eq '--') {
		push @ARGV,@args;
		last;
	}
	elsif(m/^-/) {
		push @cmd,$_;
		$_ = shift @args;
		push @cmd,$_;
	}
	else {
		push @ARGV,$_;
	}
}

sub run {
	print STDERR join(" ",@_),"\n";
	return system(@_) == 0;
}


foreach(@ARGV) {
	if(! -f $_) {
		print STDERR "Warnning: $_ not exist\n";
		next;
	}
	my $name = $_;
	$name =~ s/^.+\///;
	$name =~ s/-//g;
	if($name =~ m/^(.+)_r\d+_(\d\d\d\d)(\d\d)(\d\d)\.(.+)$/) {
		run(@cmd,'-l',"$1,Type-Archive,svndump",'-s',"$1.$5 created at $2-$3-$4",$_);
	}
	else {
		run(@cmd,'-l',"$name,repopack,Type-Archive",'-s',"$name repopack",$_);
	}
}
