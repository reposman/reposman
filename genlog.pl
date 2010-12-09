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
    open FO,'>info';
    open FS,'>status';
    print FO "$name:\n\n";
    my %svn;
    my %git;
    open FI,'-|','svn','info',$svn_url;
    print FO <FI>;
    close FI;
    open FI,'-|','svn','log','-r','HEAD',$svn_url;
    foreach(<FI>) {
        print FO $_;
        chomp;
        next unless($_);
        if(m/^-------------+/) {
            next;
        }
        elsif(m/^r(\d+)\s+\|\s+([^\|]+?)\s+\|/) {
            $svn{rev}=$1;
            $svn{author}=$2;
        }
        else {
            $svn{comment} .= $_;
        }
    }
    print FO <FI>;
    close FI;
    print FO "\n";
    print FO "Path  : git\n";
    open FI,'-|','git','--bare','log','-1','--stat','--pretty=Date  : %ci%nAuthor: %an%nCommit: %H%n%n    %s%n%n%b';
    foreach(<FI>) {
        print FO $_;
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
    print FO <FI>;
    close FI;

    chomp($svn{comment}) if($svn{comment});
    chomp($git{comment}) if($git{comment});
	if($svn{comment} eq $git{comment}) {
	    print FS "$name [SVN] r$svn{rev} [GIT] commit $git{commit}: $git{comment}";
	}
	else {
	    print FS "$name [SVN] r$svn{rev}: $svn{comment} [GIT] commit $git{commit}: $git{comment}";
	}
    close FS;
    close FO;
}

gen_log();
system('cat','info');
system('cat','status');
print "\n";
