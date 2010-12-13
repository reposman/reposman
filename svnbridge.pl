#!/usr/bin/perl -w
# $Id$
use strict;
require v5.10.0;
our $VERSION = 'v1.0';

my %OPTS;
my @OPTIONS = qw/help|h|? manual|m test|t project|p debug dump|d dump-config|dc dump-data|dd check|c pull push/;
if(@ARGV)
{
    require Getopt::Long;
    Getopt::Long::GetOptions(\%OPTS,@OPTIONS);
}
else {
    $OPTS{help} = 1;
}


#START	//map options to actions
my $have_opts;
foreach(keys %OPTS) {
	if($OPTS{$_}) {
		$have_opts = 1;
		last;
	}
}
unless($have_opts) {
	my $first_arg = shift;
	if($first_arg and $first_arg =~ m/^(help|manual|test|project|dump|dump-config|dump-data|check|list|pull|reset)$/) {
		$OPTS{$first_arg} = 1;
	}
	else {
		unshift @ARGV,$first_arg;
		$OPTS{pull} = 1;
	}
}
#END	//map options to actions

if($OPTS{help}) {
    require Pod::Usage;
    Pod::Usage::pod2usage(-exitval=>0,-verbose => 1);
    exit 0;
}
elsif($OPTS{manual}) {
    require Pod::Usage;
    Pod::Usage::pod2usage(-exitval=>0,-verbose => 2);
    exit 0;
}

use Cwd qw/getcwd/;

my $F_TEST = $OPTS{test};

my %CONFIG;
$CONFIG{svn} = "https://#1.googlecode.com/svn/#2";
$CONFIG{'git:github'} = "git\@github.com:#1/#2.git";
$CONFIG{'git:gitorious'} = "git\@gitorious.org:#1/#2.git";
$CONFIG{authors} = 'authors';
my %MACRO;

my %project;
my %sub_project;

sub run {
    print join(" ",@_),"\n";
    return 1 if($F_TEST);
    return system(@_) == 0;
}
sub error {
    print STDERR @_;
    return undef;
}

sub parse_query {
	my $query = shift;
	if($query =~ m/^([^:]+):(.*)$/) {
		return $1,$2;
	}
	else {
		return $query;
	}
}

sub get_project_data {
	my ($name,undef) = parse_query(@_);
	return $name,($project{$name} ? $project{$name} : $sub_project{$name});
}

sub parse_project_data {
    foreach my $line (@_) {
        $_ = $line;
        chomp;
        print STDERR "debug::parse_project_data>[1]",$_,"\n" if($OPTS{debug});
        foreach my $v_name (keys %MACRO) {
            s/#$v_name#/$MACRO{$v_name}/g;
        }
        print STDERR "debug::parse_project_data>[2]",$_,"\n" if($OPTS{debug});
        if(m/^\s*#([^#]+)#\s*=\s*(.+?)\s*$/) {
            my $name = $1;
            my $value = $2;
            next unless($value);
            if($name =~ m/^(?:id|id:.+|authors|user|username|email|svn|svn:.+|git|git:.+)$/) {
                $CONFIG{$name} = $value;
            }
            $MACRO{$name} = $value;
            next;
        }
		elsif(m/^\s*#/) {
			next;
		}
        #my @data = (split(/\s*\|\s*/,$_),'','','','','','','');
        my @data = split(/\s*\|\s*/,$_);
        foreach(@data) {
            s/^\s+|\s+$//;
        }
        next unless($data[0]);
        my $name = shift @data;
        if($data[0] =~ m/.+\/.+/) {
            $sub_project{$name} = \@data;
        }
        else {
            $project{$name} = \@data;
        }
    }
}

sub translate_url {
    my $url = shift;
    my $path = shift;
    if($url =~ m/#2/ and $path =~ m/^([^\/]+)\/(.+)$/) {
        my $a = $1;
        my $b = $2;
        $url =~ s/#1/$a/g;
        $url =~ s/#2/$b/g;
    }
    else {
        $url =~ s/#1/$path/g;
        $url =~ s/#2//g;
    }
    $url =~ s/\/+$//;
    return $url;
}

sub get_repo {
    my ($query_name,@repo_data) = @_;
    my %r;
	my ($name,$new_target) = parse_query($query_name);
    $r{name} = $name;
    @repo_data = ("svn:local/$name",'id',"svn:remote/$name",'id') unless(@repo_data);
	if($OPTS{debug}) {
		print STDERR "debug::get_repo> $name -  ",join("  |",@repo_data),"\n";
	}
	while(@repo_data) {
		my $push = shift @repo_data;
		next unless($push);
		if($push =~ m/\/$/) {
			$push = $push ."$name"; 
		}
		my $pull = $push;
		my $id = shift @repo_data;
		if($push =~ m/\s*([^:]+):([^:\/]+)\/(.*?)\s*$/) {
			$push = translate_url($CONFIG{"$1:$2:push"},$3) if($CONFIG{"$1:$2:push"});
		}
		if($pull =~ m/\s*([^:]+):([^:\/]+)\/(.*?)\s*$/) {
			$pull = translate_url($CONFIG{"$1:$2:pull"},$3) if($CONFIG{"$1:$2:pull"});
		}
		push @{$r{url}},[$push,$pull,$id];
	}
	if($r{url} and @{$r{url}}) {
		$r{main} = shift @{$r{url}};
	}
    return \%r;
}

sub svnsync {
	my $SOURCE = shift;
	my $DEST = shift;
	my $source_user = shift;
	my $sync_user = shift;
	use Cwd qw/getcwd/;
	my $is_localsource = 1;
	my $is_localdest = 1;
	
	my $cwd = getcwd;
	if(!$DEST) {
	    $DEST = $cwd;
	}
	elsif($DEST =~ m/:\/\//) {
	    $is_localdest = undef;
	}
	elsif($DEST =~ m/^\//) {
	}
	else {
	    $DEST = $cwd . '/' . $DEST;
	}
	if($SOURCE =~ m/:\/\//) {
	    $is_localsource = undef;
	}
	elsif($SOURCE =~ m/\//) {
	}
	else {
	    $SOURCE = $cwd . '/' . $SOURCE;
	}
	
	my $SOURCE_URL = $is_localsource ? 'file://' .  $SOURCE : $SOURCE;
	my $DEST_URL;
	if($is_localdest) {
	    $DEST_URL = 'file://' . $DEST;
	    if(! -d $DEST) {
	        print STDERR "creating local repository $DEST...\n";
	        run(qw/svnadmin create/,$DEST)
				or return error("fatal: creating repository $DEST failed\n");
	        my $hook = "$DEST/hooks/pre-revprop-change";
	        print STDERR "creating pre-revprop-change hook in $DEST...\n";
	        open FO,'>',$hook 
				or return error("fatal: creating repository hook failed\n");
	        print FO "#!/bin/sh\nexit 0\n";
	        close FO;
	        run(qw/chmod a+x/,$hook)
				or return error("fatal: creating repository hook failed\n");
	    }
	}
	else {
	    $DEST_URL = $DEST;
	}
	
	my @svnsync;
	if($source_user and $sync_user) {
	    @svnsync = ('svnsync','--source-username',$source_user,'--sync-username',$sync_user);
	}
	elsif($source_user) {
	    @svnsync = ('svnsync','--username',$source_user);
	}
	else {
	    @svnsync = ('svnsync');
	}
	print STDERR "initializing svnsync...\n";
	print STDERR "from\t$SOURCE_URL\n";
	print STDERR "to  \t$DEST_URL\n";
	run(@svnsync,'init',$DEST_URL,$SOURCE_URL);
	print STDERR "start syncing...\n";
	 run(@svnsync,'sync',$DEST_URL)	
		or return error("fatal: while syncing $DEST_URL\n");
	return 1;
}
sub unique_name {
	my ($base,$pool) = @_;
	my $idx = 2;
	my $result = $base;
	while($pool->{$result}) {
		$result = $base . $idx;
		$idx++;
	}
	return $result;
}
sub check_repo {
	my $repo = shift;
	my $main = $repo->{main};
	my @remotes = @{$repo->{url}};
	return error("fatal: no main repo specified\n") unless($main);
	return error("fatal: no mirror repos specified\n") unless(@remotes);
	foreach($main,@remotes) {
		my (undef,$url,undef) = @{$_};
		print STDERR "\nchecking $url\n";
		if(-d $url) {
			$url = 'file://' . $url;
		}
		run('svn','info',$url);
		run('svn','log','-l','2',$url);
		print STDERR "\n";
	}
}
sub pull_repo {
	my $repo = shift;
	my $main = $repo->{main};
	my $remote = shift @{$repo->{url}};
	return error("fatal: no main repo specified\n") unless($main);
	return error("fatal: no mirror repos specified\n") unless($remote);
	my ($dst,undef,$dst_id) = @{$main};
	my (undef,$src,$src_id) = @{$remote};
	return svnsync($src,$dst,$src_id,$dst_id);
}
sub push_repo {
	my $repo = shift;
	my $main = $repo->{main};
	my @remotes = @{$repo->{url}};
	return error("fatal: no main repo specified\n") unless($main);
	return error("fatal: no mirror repos specified\n") unless(@remotes);
	my (undef,$src,$src_id) = @{$main};
	foreach(@remotes) {
		my ($dst,undef,$dst_id) = @{$_};
		svnsync($src,$dst,$src_id,$dst_id);
	}
}


my $PROGRAM_DIR = $0;
$PROGRAM_DIR =~ s/[^\/\\]+$//;
my $cwd = getcwd();
my $PROJECT_FILE;

foreach my $fn (".PROJECTS","$PROGRAM_DIR/.PROJECTS","~/.svnbridge/.PROJECTS") {
    if(-f $fn) {
        $PROJECT_FILE = $fn;
        last;
    }
}
if($PROJECT_FILE) {
    if(-f $PROJECT_FILE) {
        print STDERR "reading \"$PROJECT_FILE\"... ";
        open FI,"<".$PROJECT_FILE;
        parse_project_data(<FI>);
        close FI;
    }
}

if(not (@ARGV or $PROJECT_FILE)) {
    print STDERR "input projects data line by line\n";
    print STDERR "separate fields by \"|\".\n";
    parse_project_data(<STDIN>);
}
if($OPTS{project}) {
	my $name = shift;
	parse_project_data(join('|',@ARGV),"\n");
	push @ARGV,$name;
}


my $total = scalar(keys %project) + scalar(keys %sub_project);
print STDERR "$total", $total > 1 ? " projects" : " project", ".\n";

#my $QUERY_NAME=shift;
#my @query = $QUERY_NAME ? ($QUERY_NAME) : (keys %project,keys %sub_project);
#my $count = $QUERY_NAME ? 1 : $total;
my @query = @ARGV ? @ARGV : (keys %project,keys %sub_project);


if($OPTS{'list'}) {
    $OPTS{'dump-data'} = 1;
}

if($OPTS{'dump'}) {
    $OPTS{'dump-config'} = 1;
    $OPTS{'dump-data'} = 1;
}

if($OPTS{'dump-config'}) {
    use Data::Dumper;
    print Data::Dumper->Dump([\%CONFIG],["*CONFIG"]);
}

if($OPTS{'dump-data'}) {
    use Data::Dumper;
#    my @query = $QUERY_NAME ? ($QUERY_NAME) : (keys %project,keys %sub_project);
    foreach my $query_text (@query) {
        my ($name,$pdata) = get_project_data($query_text);
        my $repo = get_repo($query_text,@{$pdata});
        print Data::Dumper->Dump([$repo],["*$name"]);
    }
}
if($OPTS{'dump-config'} or $OPTS{'dump-data'}) {
    exit 0;
}

my $idx = 0;
my $count = scalar(@query);
my $action;
my $action_sub;
if($OPTS{push}) {
	$action = 'push';
	$action_sub = \&push_repo;
}
elsif($OPTS{pull}) {
	$action = 'pull';
	$action_sub = \&pull_repo;
}
elsif($OPTS{check}) {
	$action = 'check';
	$action_sub = \&check_repo;
}
else {
	die("Invalid action specified!\n");
}

print STDERR $action . "ing $count ", $count > 1 ? "projects" : "project", " ...\n";
foreach my $query_text (@query) {
        $idx++;
		my ($name,$pdata) = get_project_data($query_text);
        print STDERR "[$idx/$count] $action" . "ing project [$name]...\n";
    	if((!$pdata) or (!ref $pdata)) {
    		print STDERR "[$idx/$count] project $name not defined.\n";
    		next;
    	}
        my $repo = get_repo($query_text,@{$pdata});
		&$action_sub($repo) or die("\n");
        print STDERR "\n";
}

exit 0;

__END__

=pod

=head1  NAME

svnbridge - svn repositories manager

=head1  SYNOPSIS

svnbridge [options] [action] [project_name|project_name:target]...
	svnbridge --pull firefox
	svnbridge pull firefox

=head1  OPTIONS

=over 12

=item B<-r>,B<--reset>

Re-configure projects

=item B<-c>,B<--check>

Check projects status

=item B<-p>,B<--project>

Target and define project from command line

=item B<-t>,B<--test>

Testing mode

=item B<--dump>

Dump CONFIG and DATA

=item B<--dump-config>

Dump CONFIG

=item B<--dump-data>

Dump DATA

=item B<-l>,B<--list>

List projects

=item B<-h>,B<--help>

Print a brief help message and exits.

=item B<--manual>,B<--man>

View application manual

=back

=head1  FILES

=item B<./.PROJECTS>

Default projects definition file, one line a project, 
echo field separated by |.

=back

=head1 PROJECTS FILE FORMAT
#MACRO1#=....
#MACRO2#=....
name	|[target]	|[user]	|repo1	|repo2	|repo3...

=head1  DESCRIPTION

git-svn projects manager

=head1  CHANGELOG

    2010-11-01  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.
	
	2010-11-25	xiaoranzzz	<xiaoranzzz@myplace.hell>
		
		* updated projects definition format
		* added two actions: checking and resetting
		* version 1.0

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut

#       vim:filetype=perl
