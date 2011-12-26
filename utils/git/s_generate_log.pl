#!/usr/bin/perl -w
use strict;

use Cwd qw/getcwd/;
my $cwd = getcwd();

my $svn_url = 'file://' . $cwd . '/svn';
my $git_dir = 'git';
$ENV{GIT_DIR}=$git_dir;

my $name = $cwd;
$name =~ s/\/+$//;
$name =~ s/^.*\///;
$name = uc($name);

sub gen_log {
	my @full_log;
	my @short_log;
    my %svn;
    my %git;
SVNLOG:
	goto GITLOG unless(-d 'svn');
    open FI,'-|','svn','info',$svn_url;
	push @full_log,<FI>;
    close FI;
    open FI,'-|','svn','log','-r','HEAD',$svn_url;
    foreach(<FI>) {
        push @full_log,$_;
        chomp;
        next unless($_);
        if(m/^-------------+/) {
            next;
        }
        elsif(m/^r(\d+)\s+\|\s+([^\|]+?)\s+\|/) {
            $svn{rev}=$1;
            $svn{author}=$2;
        }
        elsif(!$svn{comment}) {
            $svn{comment} = $_;
        }
    }
	push @full_log,<FI>;
    close FI;
GITLOG:
    push @full_log,"\nPath  : git\n";
    open FI,'-|','git','--bare','log','-1','--stat','--pretty=Date  : %ci%nAuthor: %an%nCommit: %H%n%n    %s%n%n%b';
    foreach(<FI>) {
        push @full_log,$_;
        if(m/^Author:(.+)/) {
            $git{author} = $1;
        }
        elsif(m/^Commit:\s+([a-zA-Z0-9]{8})/) {
            $git{commit} = $1;
        }
        elsif((!$git{comment}) and m/    (.+)/) {
            $git{comment} = $1;
        }
    }
	push @full_log,<FI>;
    close FI;

    chomp($svn{comment}) if($svn{comment});
    chomp($git{comment}) if($git{comment});
	push @short_log, "$name";
	if($svn{comment} and ($svn{comment} eq $git{comment})) {
	    push @short_log," [SVN] r$svn{rev} [GIT] commit $git{commit}: $git{comment}";
	}
	else {
		if($git{comment}) {
			push @short_log, " [GIT] commit $git{commit}: $git{comment}";
		}
		if($svn{comment}) {
			push @short_log, " [SVN] r$svn{rev}: $svn{comment}";
		}
	}
    open FO,'>info';
	print FO @short_log,"\n\n";
	print FO @full_log,"\n";
	print FO "="x80,"\n\n";
    close FO;
    open FS,'>status';
	print FS @short_log;
    close FS;
}

gen_log();
system('cat','info');
system('cat','status');
print "\n";
