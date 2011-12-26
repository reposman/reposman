#!/usr/bin/perl -w
use Cwd qw/getcwd/;
use File::Glob qw/bsd_glob/;
use strict;
use version '5.8';

sub run {
	print STDERR join(" ",@_),"\n";
	return system(@_)==0;
}
sub glob_git {
    my $opt = shift; 
    my $dir = shift;
    if($opt eq '-l') {
    }
    else {
        $dir = $opt;
        return if(-l $dir);
    }
 #   print STDERR "glob in $dir\n";
    my @gits;
    foreach(bsd_glob("$dir/.*"),bsd_glob("$dir/*")) {
        if(m/(?:^|[\/\\])\.+$/) {
            next;
        }
        elsif(-d $_) {
            if(m/[\.\/]git$/) {
                push @gits,$_;
            }
            else {
                my @r_git = &glob_git($_);
                push @gits,@r_git if(@r_git);
            }
        }
    }
    return @gits;
}
sub show_log {
	my $path = shift;
	my @OPTS = @_;
	$path =~ s/\/+$//;
    my $name = $path;
    my $cwd = getcwd();
    my $parent = $cwd;
	if($path =~ m/^(.+)\/([^\/]+)$/) {
        $name = $2;
        $parent = $1;
    }
	my @gits;
	if($path =~ m/\.git$/) {
		push @gits,$path;
	}
    chdir $path;
	my $pathname = $path;
	$pathname = "$pathname/" unless($pathname =~ m/\/$/);
	$pathname =~ s/^\.\/?//g;

    push @gits,glob_git("-l",".");
    my @repos;
    foreach(@gits) {
        s/^.[\/\\]+//;
        my $repo = {rel=>$_};
        $repo->{abs}="$pathname$_";
        push @repos,$repo;
    }

    chdir $cwd;
    foreach my $repo (@repos) {
		next if($repo->{abs} =~ m/^\.git$/);
		print STDERR "$repo->{abs} ...\n";
		print $repo->{abs}, ":\n";
        system("git","--git-dir",$repo->{abs},'log','--pretty=oneline','-n',5,@OPTS);
		print STDERR "\n";
		print "\n";
    }
}

my @LOG_OPT;
my @PATH;

foreach(@ARGV) {
	if(-d $_) {
		push @PATH,$_;
	}
	else {
		push @LOG_OPT,$_;
	}
}
push @PATH,'.' unless(@PATH);
foreach(@PATH) {
    show_log($_,@LOG_OPT);
}	
