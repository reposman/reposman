#!/usr/bin/perl -w
# $Id$
use strict;
our $VERSION = '2.100';
BEGIN
{
    my $PROGRAM_DIR = $0;
    $PROGRAM_DIR =~ s/[^\/\\]+$//;
    $PROGRAM_DIR = "./" unless($PROGRAM_DIR);
    unshift @INC, 
        map "$PROGRAM_DIR$_",qw{modules lib ../modules ..lib};
}
use MyPlace::Reposman::Projects;
use Cwd qw/getcwd/;
#use MyPlace::Repository;

my %OPTS;
my @OPTIONS = qw/
				help|h|? 
				manual|m 
				test|t 
				debug 
				sync|s 
				sync-all|sa 
				checkout|co|c 
				file|f:s 
				login|nu 
				no-local 
				fetch-all 
				no-remote 
				reset-config 
				to-local 
				force 
				to-remote 
				config-local
				mirror
				list|l
				query|q:s
				dump|d 
				dump-projects|dp 
				dump-config|dc 
				dump-data|dd 
				dump-hosts|dh 
				dump-target|dt 
				dump-maps|dm 
				dump-repos|dr
				dump-all|da 
				branch|b:s 
				exec-local|el:s 
				append|aa:s 
				prepend|pa:s
			/;
if(@ARGV)
{
    require Getopt::Long;
    Getopt::Long::GetOptions(\%OPTS,@OPTIONS);
	my $have_opts;
	foreach(keys %OPTS) {
		if($OPTS{$_}) {
			$have_opts = 1;
			last;
		}
	}
	unless($have_opts) {
		my $first_arg = shift;
		foreach(@OPTIONS) {
			next if(m/:s$/);
			if( $first_arg =~ m/^(:?$_)$/) {
				$OPTS{$first_arg} = 1;
				last;
			}
		}
		if(!$OPTS{$first_arg}) {
			unshift @ARGV,$first_arg;
			$OPTS{dump} = 1;
		}
	}
}
else {
    $OPTS{help} = 1;
}

my $F_TEST = $OPTS{test};
my @HG = qw/hg -v/;
my @GIT = qw/git/;
my @SVN = qw/svn/;

sub dumpdata {
	use Data::Dumper;
	my $var = shift;
	my $name = shift || '$var';
	print STDERR Data::Dumper->Dump([$var],[$name]),"\n";
	return $var;
}
sub run {
    print join(" ",@_),"\n";
    return 1 if($F_TEST);
    return system(@_) == 0;
}

sub run_s {
	return system(@_) == 0;
}

sub run_git {
	my $silent = shift;
	if($silent and $silent eq '#silent') {
		$silent = 1;
	}
	else {
		unshift @_,$silent;
		$silent = undef;
	}
	my $target = shift;
	if($target) {
		print "[$target] git ",join(" ",@_),"\n" unless($silent);
		if(-d "$target/.git") {
			return system(@GIT,'--work-tree',$target,'--git-dir',$target . '/.git',@_) == 0;
		}
		else {
			return system(@GIT,'--git-dir',$target,'--work-tree',$target,@_) == 0;
		}
	}
	else {
		run(@GIT,@_);
	}
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

sub url_get_domain {
	my $url = shift;
	if($url =~ m/.*?([^\/\\:@\.]+)\.(?:org|com|net|\.cn)/) {
		return $1;
	}
	else {
		return 'no_name';
	}
}

sub get_remotes {
	my $target = shift;
	my @query_cmd;
	if(!$target) {
		@query_cmd = qw/git remote/;
	}
	elsif(-d "$target/.git") {
		@query_cmd = (
			'git',
			'--git-dir',"$target/.git",
			'--work-tree',$target,
			'remote'
		);
	}
	else {
		@query_cmd = ('git','--git-dir',$target,'remote');
	}
    my @remotes;
    open FI,"-|",@query_cmd or return undef;
    while(<FI>) {
        chomp;
        push @remotes,$_ if($_);
    }
    close FI;
	return @remotes;
}

sub git_add_remotes {
	my ($target,@remotes) = @_;
	my %pool;
	my %old_remotes;
	foreach(get_remotes($target)) {
		$old_remotes{$_} = 1;
	}
	foreach(@remotes) {
		my $url = $_->{'push'};
		my $name = unique_name(url_get_domain($url),\%pool);
		$pool{$name} = 1;
		run_git("#silent",$target,qw/remote rm/,$name) if($old_remotes{$name});
		print STDERR "\t Add remote [$name] $url\n";
		run_git('#silent',$target,qw/remote add/,$name,$url);
	}
}
sub hg_add_remote {
	my ($repo,$target,@remotes) = @_;
	my %pool;
	if(-f "$target/.hg/hgrc") {
		run('cp','-av',"$target/.hg/hgrc","$target/.hg/hgrc.bak");
	}
	open FO,">","$target/.hg/hgrc" or return error("$!\n");
	print FO '[paths]',"\n";
	foreach(@remotes) {
		my $name = unique_name('default',\%pool);
		$pool{$name} = 1;
		print FO "$name = $_->{'pull'}\n";
		print FO "$name-push = $_->{'push'}\n";
	}
	close FO;
#	my @HGCONFIG = (@HG,qw/-R/,$target,'--config');
#	foreach(keys %remotes) {
#		run(@HGCONFIG,"paths.$_=$remotes{$_}->{'pull'}");
#		run(@HGCONFIG,"paths.$_-push=$remotes{$_}->{'pull'}");
#	}
	run(@HG,'-R',$target,'paths');
}
sub error {
    print STDERR @_;
    return undef;
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
sub git_push_remote {
    my @remotes = get_remotes();
    if(@remotes) {
        my $idx=0;
        my $count=@remotes;
        foreach(@remotes) {
            $idx++;
            my $url = `git config --get "remote.$_.url"`;
            chomp($url);
            print "[$idx/$count]pushing to [$_] $url ...\n";
            if(system(qw/git push/,$_,@_)!=0) {
                print "[$idx/$count]pushing to [$_] failed\n";
                return undef;
            }
        }
    }
    else {
       print "NO remotes found, stop pushing\n";
       return undef;
    }
    return 1;
}

sub checkout_repo {
	my $repo = shift;
	my $target = $repo->{target};
	my $name = $repo->{name};
	if($repo->{hg} and !$OPTS{'no-hg'}) {
		my $local = shift @{$repo->{hg}};
		my $source = shift @{$repo->{hg}};
		unless(-d $target) {
			run(@HG,'clone',$source->{'pull'},$target);
		}
		else {
			#run(@HG,'-R',$target,qw/update -C/);
			run(@HG,"init",$target);
			run(@HG,'-R',$target,qw/pull -f/,$source->{'pull'});
			run(@HG,'-R',$target,qw/update/);
		}
		hg_add_remote($repo,$target,$source,@{$repo->{hg}});
		run(@HG,'-R',$target,'tip');
		run(@HG,'-R',$target,'summary');
	}
	if($repo->{svn} and !$OPTS{'no-svn'}) {
		my $local = shift @{$repo->{svn}};
		my $source = shift @{$repo->{svn}};
		run(@SVN,'checkout','--force',$source->{'push'} . "/trunk",$target);
	}
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		my $source = $local;
		if($OPTS{'reset-config'} and -d $target) {
			print STDERR "[$target] GIT Reset\n";
			run('rm','-frv',"$target/.git/config","$target/.git/refs/remotes");
		}
		if($OPTS{'no-local'}) {
			$source = shift @{$repo->{git}};
		}
		else {
			unless(-d $local->{'push'}) {
				run_git(undef,'init','--bare',$local->{'push'});
			}
		}
		unless(-d $target) {
			run_git(undef,'clone',$source->{'push'},$target);
		}
		else {
			run_git(undef,"init",$target);
			run_git($target,qw/remote rm origin/);
			run_git($target,qw/remote add origin/,$source->{'push'});
		}
		if(!$OPTS{'no-remote'}) {
			git_add_remotes($target,@{$repo->{git}});
		}
		if($OPTS{'fetch-all'}) {
			run_git($target,qw/fetch --all/);
		}
		else {
			run_git($target,qw/fetch origin/);
		}
		run_git($target,qw/remote -v/);
		run_git($target,qw/branch -av/);
	}
	return 1;
}
sub sync_repo {
	my $repo = shift;
	my $first_only = shift;
#	my $target = $repo->{target}; #ignore this checkout point
	my $name = $repo->{name};
	if($repo->{hg} and !$OPTS{'no-hg'}) {
		my $local = shift @{$repo->{hg}};
		my $target = $local->{'push'};
		my $source = shift @{$repo->{hg}};
		unless(-d $target) {
			run(@HG,'clone','-U',$source->{'pull'},$target);
		}
		else {
			#run(@HG,'-R',$target,qw/update -C/);
			run(@HG,'-R',$target,qw/pull -f/,$source->{'pull'});
		}
		unless($first_only) {
			foreach(@{$repo->{hg}}) {
				run(@HG,'-R',$target,'push','-f',$_->{'push'});
			}
		}
		run(@HG,'-R',$target,'tip');
		run(@HG,'-R',$target,'summary');
	}
	if($repo->{svn} and !$OPTS{'no-svn'}) {
		my $local = shift @{$repo->{svn}};
		my $target = $local->{'push'};
		my $source = shift @{$repo->{svn}};
		$repo->{svn_source} = $source;
		svnsync($source->{'pull'},$target,$source->{id},$local->{id});
		unless($first_only) {
			foreach(@{$repo->{svn}}) {
				svnsync($source->{'pull'},$_->{'push'},$source->{'id'},$_->{'id'});
			}
		}
	}
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		my $target = $local->{'push'};
		my $source = shift @{$repo->{git}};
		$repo->{git_source} = $source;
		run_git(undef,'--bare','clone',$source->{'pull'},$target);
		unless($first_only) {
			foreach(@{$repo->{git}}) {
				run_git(undef,'--bare','--git-dir',$target,'push',$_->{'push'});
			}
		}
	}
	return 1;
}

sub sync_to_local {
	my $repo = shift;
	my $first_only = shift;
#	my $target = $repo->{target}; #ignore this checkout point
	my $name = $repo->{name};
	if($repo->{hg} and !$OPTS{'no-hg'}) {
		return print STDERR("\nHG repositories support need testing\n");
		my $local = shift @{$repo->{hg}};
		my $target = $local->{'push'};
		my $source = shift @{$repo->{hg}};
		unless(-d $target) {
			run(@HG,'clone','-U',$source->{'pull'},$target);
		}
		else {
			#run(@HG,'-R',$target,qw/update -C/);
			run(@HG,'-R',$target,qw/pull -f/,$source->{'pull'});
		}
		unless($first_only) {
			foreach(@{$repo->{hg}}) {
				run(@HG,'-R',$target,'push','-f',$_->{'push'});
			}
		}
		run(@HG,'-R',$target,'tip');
		run(@HG,'-R',$target,'summary');
	}
	if($repo->{svn} and !$OPTS{'no-svn'}) {
		return print STDERR ("\nSVN repositories support need testing\n");
		my $local = shift @{$repo->{svn}};
		my $target = $local->{'push'};
		my $source = shift @{$repo->{svn}};
		$repo->{svn_source} = $source;
		svnsync($source->{'pull'},$target,$source->{id},$local->{id});
		unless($first_only) {
			foreach(@{$repo->{svn}}) {
				svnsync($source->{'pull'},$_->{'push'},$source->{'id'},$_->{'id'});
			}
		}
	}
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		my $target;
		if($repo->{_target} and $repo->{target}) {
			$target = $repo->{target};
		}
		else {
			$target = $local->{'push'};
		}
		my $source = shift @{$repo->{git}};
		$repo->{git_source} = $source;
		if(-d $target and $OPTS{'force'}) {
			run('rm','-fr',$target);
		}
		run_git(undef,'--bare','clone',$source->{'pull'},$target);
		run_git('#silent',$target,qw/remote rm origin/);
		run_git($target,qw/remote add origin/,$source->{'push'});
		if(!$OPTS{'no-remote'}) {
			git_add_remotes($target,@{$repo->{git}});
		}
		if($OPTS{'fetch-all'}) {
			run_git($target,qw/fetch --all/);
		}
		run_git($target,qw/remote -v/);
		run_git($target,qw/branch -av/);
	}
	return 1;
}

sub local_to_remote {
	my $repo = shift;
	my $first_only = shift;
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		print STDERR "Source: ", $local->{pull},"\n";
		if(! -d $local->{pull}) {
			print STDERR "\t Error directory not exists.\n";
		}
		else {
			my @push = 'push';
			my @append;
			push @append, $OPTS{'branch'} if($OPTS{branch});
			if($OPTS{'mirror'}) {
				@push = ('push','--mirror');
			}
			elsif($OPTS{'force'}) {
				@push = qw/push --force/;
			}
			foreach(@{$repo->{git}}) {
				print STDERR "  Dest: ",$_->{push}, " (", join(" ",@push), ") \n";
				run_s('git','--git-dir',$local->{pull},'--bare',@push ,$_->{push},@append);
			}
		}
	}
	return 1;
}

sub config_local {
	my $repo = shift;
	my $first_only = shift;
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		print STDERR "Source: ", $local->{pull},"\n";
		if(! -d $local->{pull}) {
			print STDERR "\t Error directory not exists.\n";
		}
		else {
			my @remotes = get_remotes($local->{pull},1);
			foreach(@remotes) {
				print STDERR "\t Remove old remote [$_]\n";
				run_s('git','--git-dir',$local->{pull},'--bare','remote','rm',$_);
			}
			git_add_remotes($local->{pull},@{$repo->{git}});
			run_git($local->{pull},qw/remote -v/);
		}
	}
	return 1;
}


sub list_repo {
	return 1;
	my $repo = shift;
	my $verbose = shift;
	if($verbose) {
		use Data::Dumper;
		print Data::Dumper::Dump([$repo],["*$repo->{name}"]),"\n";
	}
	else {
		print "id: $repo->{shortname} [$repo->{type}]\n";
		print "name: $repo->{name}\n";
		print "localname: $repo->{localname}\n";
		print "checkout point: $repo->{target}\n";
	}
}
sub query_repo {
	my $repo = shift;
	return 1 unless($OPTS{query});
	my $property = $OPTS{query};
	my $value = $repo->{$property};
	if($property eq '_all') {
		print Data::Dumper->Dump([$repo],["*$repo->{shortname}"]);
	}
	elsif(ref $value) {
		print Data::Dumper->Dump([$value],["*$repo->{shortname}" . '->{' . "$property" . '}']);	
	}
	else {
		print "$property = $value\n";
	}
	return 1;
}

sub exec_local {
	my $repo = shift;
	my $first_only = shift;
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		print STDERR "Target: ", $local->{pull},"\n";
		if(! -d $local->{pull}) {
			print STDERR "\t Error directory not exists.\n";
		}
		else {
			my @cmds = split(/\s+/,$OPTS{'exec-local'});
			foreach(@cmds) {
				if(m/^\$(.+?)(\d+)$/) {
					$_ = $repo->{git}->[$2]->{$1};
				}
			}
			my @append = $OPTS{'append'} ? split(/\s+/,$OPTS{'append'}): ();
			my @prepend = $OPTS{'prepend'} ? split(/\s+/,$OPTS{'prepend'}) : ();
			my $app = shift @cmds;
			if($app eq 'git') {
				run(
					'git',
					@prepend,
					'--git-dir',$local->{pull},
					@cmds,
					@append,
				);
			}
			else {
				run($app,@cmds,@append);
			}
		}
	}
	return 1;
}


sub initialize {
	my $config = shift;
	my $file;
	if($OPTS{file}) {
		$file=$OPTS{file};
	}
	else {
		foreach my $fn (".PROJECTS","~/.PROJECTS","~/.reposman/PROJECTS","/etc/reposman/PROJECTS") {
			if(-f $fn) {
				$file = $fn;
		        last;
			}
		}
	}	
	if($file) {
		if(-f $file) {
			print STDERR "reading \"$file\"... ";
			return $config->from_file($file);
	    }
	}
	if(not (@ARGV or $file)) {
		print STDERR "Input projects data line by line\n";
		return $config->from_strings(<STDIN>);
	}
}


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



my $PROGRAM_DIR = $0;
$PROGRAM_DIR =~ s/[^\/\\]+$//;
my $cwd = getcwd();


my $config = MyPlace::Reposman::Projects->new();
initialize($config);

my @names = $config->get_names();

my $total = scalar(@names);
print STDERR "$total", $total > 1 ? " projects" : " project", ".\n";

my @query = @ARGV;
if(!@query and -f ".git/config") {
	my $query = qx/git config --get reposman.query/;
	chomp($query);
	if($query) {
		@query = split(/\s*,\s*/,$query);
	}
}
my @targets;
if(@query) {
	@targets = $config->query_repos(@query);
}
else {
	@targets = $config->get_repos();
}


if($OPTS{'dump-all'}) {
	foreach (qw/
		dump
		dump-data 
		dump-config
		dump-maps
		dump-hosts
		dump-projects
		dump-repos
	/) {
		$OPTS{$_} = 1;
	}
}
if($OPTS{'dump'}) {
    $OPTS{'dump-target'} = 1;
}

use Data::Dumper;
print Data::Dumper->Dump([$config->get_raw()],["*DATA"]) if($OPTS{'dump-data'});
print Data::Dumper->Dump([$config->get_config()],["*CONFIG"]) if($OPTS{'dump-config'});
print Data::Dumper->Dump([$config->get_maps()],["*MAPS"]) if($OPTS{'dump-maps'});
print Data::Dumper->Dump([$config->get_hosts()],["*HOSTS"]) if($OPTS{'dump-hosts'});
print Data::Dumper->Dump([$config->get_projects()],["*PROJECTS"]) if($OPTS{'dump-projects'});
print Data::Dumper->Dump([$config->get_repos()],["*REPOS"]) if($OPTS{'dump-repos'});
print Data::Dumper->Dump([\@targets],["*targets"]) if($OPTS{'dump-target'});
if($OPTS{'dump'} or $OPTS{'dump-target'}) {
	exit 0;
}

my $idx = 0;
my $count = scalar(@targets);
my $action;
my $action_sub;
if($OPTS{checkout}) {
	$action = 'checkout';
	$action_sub = \&checkout_repo;
}
elsif($OPTS{check}) {
	$action = 'check';
	$action_sub = \&check_repo;
}
elsif($OPTS{sync}) {
	$action = 'sync';
	$action_sub = sub {eval 'sync_repo(@_,1)';};
}
elsif($OPTS{'sync-all'}) {
	$action = 'sync-all';
	$action_sub = \&sync_repo;
}
elsif($OPTS{'to-local'}) {
	$action = 'to-local';
	$action_sub = \&sync_to_local;
}
elsif($OPTS{'to-remote'}) {
	$action = 'Push';
	$action_sub = \&local_to_remote;
}
elsif($OPTS{'config-local'}) {
	$action = 'Configuring local';
	$action_sub = \&config_local;
}
elsif($OPTS{'list'}) {
	$action = 'List';
	$action_sub =\&list_repo;
}
elsif($OPTS{'query'}) {
	$action = 'Query';
	$action_sub = \&query_repo;
}
elsif($OPTS{'exec-local'}) {
	$action = 'Exec Local';
	$action_sub = \&exec_local;
}
else {
	die("Invalid action specified!\n");
}

print STDERR "To $action $count ", $count > 1 ? "projects" : "project", " ...\n";
foreach my $repo (@targets) {
        $idx++;
        print STDERR "[$idx/$count] $action" . " project [$repo->{name}]\n";
		&$action_sub($repo) or die("\n");
        print STDERR "\n";
}

exit 0;

__END__

=pod

=head1  NAME

reposman - svn,git,mercurial repositories manager

=head1  SYNOPSIS

reposman [options] [action] [project_name|project_name:target]...
	reposman --sync ffprofile
	reposman sync ffprofile

=head1  OPTIONS

=over 12

=item B<-f>,B<--file>

Specify projects data file, default is .PROJECTS

=item B<-s>,B<--sync>

Sync repositories

=item B<-r>,B<--reset>

Re-configure projects

=item B<-c>,B<--check>

Check projects status

=item B<-t>,B<--test>

Testing mode

=item B<--dump>, B<--dump-target>

Dump data for targets 

=item B<--dump-config>

Dump CONFIG

=item B<--dump-data>

Dump bare DATA

=item B<--dump-projects>

Dump all projects data

=item B<--dump-hosts>

Dump all hosts data

=item B<--dump-all>

Dump everything

=item B<-l>,B<--list>

List projects

=item B<--no-local>

Ignore local repositories

=item B<--fetch-all>

Instead of fetching the origin, fetch all repositories

=item B<--reset-config>

Reset .git/config and .git/refs/remotes

=item B<--to-remote>

Push local repository to remotes

=item B<--config-local>

Re-configure local repositories

=item B<-b>,B<--branch> 

Specify which branch 

=item B<--exec-local>,B<-el>

Execute commands in local reposotiry

=item B<--append>,B<-aa>

Append command argments

=item B<--prepend>,B<-pa>

Prepend command arguments

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

	2011-2-13	xiaoranzzz  <xiaoranzzz@myplace.hell>

		* only checkout the origin repository
		* added options 'no-local' and 'fetch-all'

	2011-2-15	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add definition localname:map
		* add option 'reset-config'

	2011-03-27	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add repository url definition macros e.g. g:gh/#localname# 
		* add action 'to-remote'
		* add action 'config-local'

	2011-11-24	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* re-design data file format.
		* update program and module to reflect format changing
		* version 2.000

	2011-12-01	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add option --branch|-b
	
	2011-12-05	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add options --exec-locak, --append, --prepend

	2011-12-06	xiaoranzzz	<xiaoranzzz@myplace.hell>
		
		* move PROJECTS related codes to MyPlace::Reposman::Projects
		* version 2.100

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut

#       vim:filetype=perl
