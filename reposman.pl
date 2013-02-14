#!/usr/bin/perl -w
# $Id$
use strict;
our $APPNAME = "reposman";
our $APPDESC = "a repositories manager";
our $VERSION = '2.200';
BEGIN
{
    my $PROGRAM_DIR = $0;
    $PROGRAM_DIR =~ s/[^\/\\]+$//;
    $PROGRAM_DIR = "./" unless($PROGRAM_DIR);
    unshift @INC, 
        map "$PROGRAM_DIR$_",qw{modules lib ../modules ..lib};
}
use MyPlace::Script::Message;
use MyPlace::Reposman::Projects;
use Cwd qw/getcwd/;
#use MyPlace::Repository;

my %OPTS;
my %SUBCMDS;
foreach(qw/
	help|h
	manual
	sync|s
	sync-all|sa
	checkout|co|c
	reset-target
	pull 
	push
	config|conf
	list|l
	query|q
	dump|d 
	exec|e 
/) {
	if(m/([^|]+)\|/) {
		$SUBCMDS{$1} = $_;
	}
	else {
		$SUBCMDS{$_} = $_;
	}
}
my @GLOBAL_OPTIONS = qw/
				help|h|? 
				manual|man
				test|t 
				debug|D 
				file|f:s 
				fetch-all 
				login|u
				no-local|nl
				no-remotes|nr
				branch|b:s 
				append|aa:s 
				prepend|pa:s
				remotes|r:s
				commands|c:s
				property|p:s
				reset-config|rc
				dump-projects|dp 
				dump-config|dc 
				dump-data|dd 
				dump-hosts|dh 
				dump-target|dt 
				dump-maps|dm 
				dump-repos|dr
				dump-all|da 
			/;

my $F_TEST = $OPTS{test};
my @HG = qw/hg -v/;
my @GIT = qw/git/;
my @SVN = qw/svn/;

my %Commands;

sub def_cmd {
	my $def = shift;
	return unless $def->{name};
	my $name = $def->{name};
	$Commands{$name} = {} unless($Commands{$name});
	my $cmd = $Commands{$name};
	foreach my $key (qw/desc prompt options usage summary help class/) {
		$cmd->{$key} = $def->{$key} if($def->{$key});
	}
	if(!$cmd->{class}) {
		$cmd->{class} = 0;
	}
	return $cmd;
}

sub get_action {
	my $name = shift;
	$name =~ s/[^a-zA-Z]/_/g;
	$name = "do_$name";
	if(defined $main::{$name}) {
		return $main::{$name};
	}
	else {
		return undef;
	}
}

sub dump_var {
	use Data::Dumper;
	my $var = shift;
	my $name = shift || '$var';
	print STDERR Data::Dumper->Dump([$var],[$name]),"\n";
	return $var;
}
sub empty_unless {
	my $s = shift;
	my $t = shift;
	if($s) {
		return sprintf($t,$s);
	}
	return '';
}
sub run {
    app_message 'Execute:',join(" ",@_),"\n";
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
		app_message "[$target] git ",join(" ",@_),"\n" unless($silent);
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

sub git_get_remotes {
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
	foreach(git_get_remotes($target)) {
		$old_remotes{$_} = 1;
	}
	foreach(@remotes) {
		my $url = $_->{'push'};
		my $name = unique_name(url_get_domain($url),\%pool);
		$pool{$name} = 1;
		run_git("#silent",$target,qw/remote rm/,$name) if($old_remotes{$name});
		app_message "\t Add remote [$name] $url\n";
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
    return app_error(@_);
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
	        app_message("creating local repository $DEST...\n");
	        run(qw/svnadmin create/,$DEST)
				or return error("fatal: creating repository $DEST failed\n");
	        my $hook = "$DEST/hooks/pre-revprop-change";
	        app_message "creating pre-revprop-change hook in $DEST...\n";
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
	app_message "initializing svnsync...\n";
	app_message "from\t$SOURCE_URL\n";
	app_message "to  \t$DEST_URL\n";
	run(@svnsync,'init',$DEST_URL,$SOURCE_URL);
	app_message "start syncing...\n";
	 run(@svnsync,'sync',$DEST_URL)	
		or return error("fatal: while syncing $DEST_URL\n");
	return 1;
}

def_cmd({
	name=>		"checkout",
	desc=>		"Checkout repositories to local",
	prompt=>	"Checking out %s",
	usage=>		"[options] [queires]",
	options=>	{
			'reset-config'=>"--reset\tReset configuration",
			'no-local'=>"--no-local\tCheckout from remote repository",
		},
});
sub do_checkout {
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
			app_message "[$target] GIT Reset\n";
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
		if(!$OPTS{'no-remotes'}) {
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
		return app_message("\nHG repositories support need testing\n");
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
		return app_message ("\nSVN repositories support need testing\n");
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
		if(!$OPTS{'no-remotes'}) {
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


sub config_local {
	my $repo = shift;
	my $first_only = shift;
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		app_message "Source: ", $local->{pull},"\n";
		if(! -d $local->{pull}) {
			app_message "\t Error directory not exists.\n";
		}
		else {
			my @remotes = git_get_remotes($local->{pull},1);
			foreach(@remotes) {
				app_message "\t Remove old remote [$_]\n";
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
		app_message Data::Dumper::Dump([$repo],["*$repo->{name}"]),"\n";
	}
	else {
		app_message "id: $repo->{shortname} [$repo->{type}]\n";
		app_message "name: $repo->{name}\n";
		app_message "localname: $repo->{localname}\n";
		app_message "checkout point: $repo->{target}\n";
	}
}

sub get_property {
	my $repo = shift;
	@_ = ('name') unless(@_);
	my %r;
	my $name = $repo->{name};
	my $point = '->';
	foreach(@_) {
		if(m/^\s*([^\[]+)?\s*\[\s*(\d+)\s*\]\s*$/) {
			$r{$name . $point . $_} = $repo->{$1}->[$2];
		}
		elsif(m/^\s*([^\[]+)?\s*\[\s*(\d+)\s*\]\s*$/) {
			$r{$name . $point . $_} = $repo->{$1}->{$2};
		}
		elsif($_ eq '_all') {
			$r{$name} = $repo;
		}
		else {
			$r{$name . $point . $_} = $repo->{$_};
		}
	}
	return %r;
}

sub query_repo {
	my $repo = shift;
	if(!$OPTS{property}) {
		$OPTS{'property'} = 'shortname';
	}
	my $property = $OPTS{property};
	my $value = $repo->{$property} || '';
	my %report = get_property($repo,$property);
	foreach(keys %report) {
		if(ref $report{$_}) {
			print(Data::Dumper->Dump([$report{$_}],['*' . $_]),"\n")
		}
		else {
			print "$_ = $report{$_}\n"
		}
	}
	return 1;
}

sub exec_local {
	my $repo = shift;
	my $first_only = shift;
	$OPTS{'commands'} = 'git config -l --local' unless($OPTS{'commands'});
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		app_message "Target: ", $local->{pull},"\n";
		if(! -d $local->{pull}) {
			app_message "\t Error directory not exists.\n";
		}
		else {
			my @cmds = split(/\s+/,$OPTS{'commands'});
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
def_cmd({
	name=>		'dump',
	class=>		'2',
	desc=>		'Dump repositories data',
	prompt=>	'Dumping repository %s',
	usage=>		'[options] [queries]',
	options=>	{
			all=>"--all\tDump all information",
			data=>"--data\tDump data",
			config=>"--config\tDump config",
			maps=>"--maps\tDump maps",
			hosts=>"--hosts\tDump hosts",
			projects=>"--projects\tDump projects",
			repos=>"--repos\tDump repositories",
			targets=>"--targets\tDump targets",
		},
});
sub do_dump {
	my $config = shift;
	my $targets = shift;
	my $have_arg = undef;
	if($OPTS{'all'}) {
		foreach (qw/
			data 
			config
			maps
			hosts
			projects
			repos
			target
		/) {
			$OPTS{$_} = 1;
		}
		$have_arg = 1;
	}
	if(!$have_arg) {
		foreach(qw/
			data	config
			maps	hosts
			repos	projects
			target
			/) {
				if($OPTS{$_}) {
					$have_arg = 1;
					last;
				}
		}
	}		
	$OPTS{'target'} = 1 unless($have_arg);
	dump_var($config->get_raw(),"*DATA") if($OPTS{'data'});
	dump_var([$config->get_config()],["*CONFIG"]) if($OPTS{'config'});
	dump_var([$config->get_maps()],["*MAPS"]) if($OPTS{'maps'});
	dump_var([$config->get_hosts()],["*HOSTS"]) if($OPTS{'hosts'});
	dump_var([$config->get_projects()],["*PROJECTS"]) if($OPTS{'projects'});
	dump_var([$config->get_repos()],["*REPOS"]) if($OPTS{'repos'});
	dump_var([$targets],["*targets"]) if($OPTS{'target'});
	return 0;
}

sub reset_target {
	my $repo = shift;
	my $name = $repo->{name};
	my $target = $repo->{target};
	return error('Target not exists: ' . $target) unless(-d $target);
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};
		app_message "Source: $target\n";
			my @remotes = git_get_remotes($target,1);
			foreach(@remotes) {
				app_message "\t Remove old remote [$_]\n";
				run_git($target,qw/remote rm/,$_);
			}
			run_git($target,qw/remote add origin/,$local->{'push'});
			git_add_remotes($target,@{$repo->{git}}) unless($OPTS{'no-remotes'});
			run_git($target,qw/remote -v/);
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
		foreach my $fn (".PROJECTS","~/.PROJECTS","$ENV{HOME}/.reposman/PROJECTS","/etc/reposman/PROJECTS") {
			if(-f $fn) {
				$file = $fn;
		        last;
			}
		}
	}	
	if($file) {
		if(-f $file) {
			app_message "Reading \"$file\" ...\n";
			return $config->from_file($file);
	    }
	}
	if(not (@ARGV or $file)) {
		app_message "Input projects data line by line\n";
		return $config->from_strings(<STDIN>);
	}
}


def_cmd({
	class=>		1,
	name=>		"help",
	desc=>		"Display usage text",
	prompt=>	"Display usage text for %s",
	help=>		"[command]",
});

sub do_help {
	my $what = shift @ARGV;
	my $s = "    ";
	if(!$what) {
		$what = "help";
		if($OPTS{manual}) {
			require Pod::Usage;
			Pod::Usage::pod2usage(-exitval=>0,-verbose => 2);
		}
		else {
			require Pod::Usage;
			Pod::Usage::pod2usage(-exitval=>0,-verbose => 1);
		}
		#print STDERR "$APPNAME\n$s- $APPDESC\n";
		#print STDERR "Usage: $APPNAME [command] [options] ...\n";
		#print STDERR "Supported commands are:\n";
		#foreach (keys %Commands) {
		#	print STDERR "$s$_\t$Commands{$_}->{desc}\n";
		#}
		return 0;
	}
	my $action = $Commands{$what};

	if(!$action) {
		print STDERR "Error command undefined: $what\n";
		return 2;
	}

	print STDERR "$APPNAME $what\n";
	print STDERR empty_unless($action->{desc},"$s- %s\n");
	print STDERR empty_unless($action->{usage},"Usage: $what %s\n");
	if($action->{options}) {
		print STDERR "Options:\n";
		foreach(keys %{$action->{options}}) {
			print STDERR "$s$action->{options}->{$_}\n";
		}
	}
	print STDERR empty_unless($action->{summary},"%s\n");
	return 0;
}

def_cmd({
	name=>		'push',
	prompt=>	'Syncing %s to remotes',
	desc=>		'Syncing repositories to remotes',
	usage=>		'[optoins]',
	summary=>	'',
	options=>	{
				'mirror'=>"--mirror\tMirroring repositories",
				'force'=>"--force\tForce mode, override remots",
				'all'=>"--all\tPush all branches",
				'tags'=>"--tags\tPush tags",
				'remotes'=>"--remotes\tPush to specified remotes",
		},
});
sub do_push {
	my $repo = shift;
	my $first_only = shift;
	my $remote_exp = $OPTS{'remotes'} || '.';
	if($repo->{git} and !$OPTS{'no-git'}) {
		my $local = shift @{$repo->{git}};

		#Select old matched remote.
		my @remotes = grep {$_->{push} =~ m/$remote_exp/;} @{$repo->{git}};

		app_message "Source: ", $local->{pull},"\n";
		return app_error ("Error: remotes not found.\n") unless(@remotes);
		return app_error "Error directory not exists.\n" unless(-d $local->{pull});
		my @push = ('push');
		my @prepend = $OPTS{'prepend'} || ();
		my @append = $OPTS{'append'} || ();
		push @append, $OPTS{'branch'} if($OPTS{branch});
		if($OPTS{'mirror'}) {
			push @push,'--mirror';
		}
		if($OPTS{'force'}) {
			push @push,'--force';
		}
		if($OPTS{'all'}) {
			push @push,'--all';
		}
		foreach(@remotes) {
			#next unless($_->{push} =~ m/$remote_exp/);
			#or $_->{host} =~ m/$remote_exp/);
			app_message "  Dest: ",$_->{push}, " (", join(" ",@push), ") \n";
			run_s('git',@prepend,'--git-dir',$local->{pull},'--bare',@push ,$_->{push},@append);
		}
	}
	return 1;
}
#if($command eq 'checkout') {
#	$msg_item = 'Checking out %s';
#	$action_sub = \&checkout_repo;
#}
#elsif($command eq 'check') {
#	$msg_item = 'Checking %s';
#	$action_sub = \&check_repo;
#}
#elsif($command eq 'sync') {
#	$msg_item = 'Syncing %s';
#	$action_sub = sub {eval 'sync_repo(@_,1)';};
#}
#elsif($command eq 'sync-all') {
#	$msg_item = 'Syncing all for %s';
#	$action_sub = \&sync_repo;
#}
#elsif($command eq 'pull') {
#	$msg_item = 'Syncing %s to local';
#	$action_sub = \&sync_to_local;
#}
#elsif($command eq 'push') {
#	$msg_item = 'Syncing %s to remotes';
#	$action_sub = \&local_to_remote;
#}
#elsif($command eq 'config') {
#	$msg_item = 'Configuring %s';
#	$action_sub = \&config_local;
#}
#elsif($command eq 'list') {
#	$msg_action = "Get %s:";
#	$msg_item = "%s";
#	$action_sub =\&list_repo;
#}
#elsif($command eq 'query') {
#	$msg_item = 'Quering %s';
#	$action_sub = \&query_repo;
#}
#elsif($command eq 'exec') {
#	$msg_item = 'Executing commands for %s';
#	$action_sub = \&exec_local;
#}
#elsif($command eq 'reset-target') {
#	$msg_item = 'Resetting %s';
#	$action_sub = \&reset_target;
#}
#else {
#	app_error ("Invalid action specified!\n");
#	exit 1;
#}


my $command;
my $action;
my $actor;
my @options = ();

if(@ARGV) {
	my $first = shift @ARGV;
	foreach(keys %SUBCMDS) {
		if($first eq $_) {
			$command = $_;
			last;
		}
	}
	if(!$command) {
		foreach(keys %SUBCMDS) {
			if($first =~ m/^$SUBCMDS{$_}$/) {
				$command = $_;
				last;
			}
		}
	}
	if(!$command) {
		unshift @ARGV,$first;
	}
}
else {
	$command = 'help';
	$OPTS{'help'} = 1;
}
$action = $Commands{$command};
if(!$action) {
	app_error("Command not defined: $command\n");
	exit 10;
}
$actor = get_action($command);
if(!$actor) {
	app_error("Action not defined by command $command\n");
	exit 11;
}
@options = ();
if($action->{options}) {
	foreach(keys %{$action->{options}}) {
		push @options,$_;
	}
}
push @options,@GLOBAL_OPTIONS;
use Getopt::Long;
Getopt::Long::GetOptions(\%OPTS,@options);



if($action->{class} == 1) {
	exit &$actor();
}


my $config = MyPlace::Reposman::Projects->new();
initialize($config);

my @names = $config->get_names();

my $total = scalar(@names);
app_message ($total,($total > 1 ? " projects" : " project")," read.\n");

my @query = @ARGV;
if(!@query) {
	my $query = qx/git config --get reposman.query/;
	chomp($query);
	if($query) {
		@query = split(/\s*,\s*/,$query);
		app_message("Load queries from GIT CONFIG\n");
	}
}
if(!@query) {
	my $max_level = 12;
	my $file = '.reposman';
	while($max_level--) {
		if(@query) {
			app_message("Load queries from file \"$file\"\n");
			last;
		};
		unless(-f $file) {
			$file = '../' . $file;
			next;
		}
		if(open FI,"<",$file) {
			foreach(<FI>) {
				chomp;
				next unless($_);
				push  @query, split(/\s*,\s*/);
			}
		}
	}
}
my @targets;
if(@query) {
	@targets = $config->query_repos(@query);
}
else {
	@targets = values %{$config->get_repos()};
}

if($action->{class} == 2) {
	#do_dump
	exit &$actor($config,\@targets);
}

my $idx = 0;
my $count = scalar(@targets);
my $msg_action;


my $message = sprintf(
			$msg_action || ucfirst($command . " %s"),
			$count > 1 ? "$count projects" : "1 project"
		);
app_message($message . "\n");
my $r = 0;
foreach my $repo (@targets) {
        $idx++;
		$message = sprintf($action->{prompt}, "$repo->{name} \[$repo->{target}\/\]");
        app_message "[$idx/$count] $message\n";
		$r = &$actor($repo,\@targets,$config) or die("\n");
}

exit $r;

__END__

=pod

=head1  NAME

reposman - svn,git,mercurial repositories manager

=head1  SYNOPSIS

reposman [options] command [args...] [query[:target]]...

	reposman sync ffprofile
	reposman push --remotes 'github' reposman websaver2

=head2 COMMANDS
	
	sync, push, pull, list, query, checkout 
	reset, config, reset-config, dump, exec

=head1  OPTIONS

=item B<-f>,B<--file>

Specify projects data file, default is .PROJECTS

=item B<-t>,B<--test>

Testing mode

=item B<--no-local>

Ignore local repositories

=item B<--fetch-all>

Instead of fetching the origin, fetch all repositories

=item B<-b>,B<--branch> 

Specify which branch 

=item B<--append>,B<-aa>

Append command argments

=item B<--prepend>,B<-pa>

Prepend command arguments

=item B<-h>,B<--help>

Print a brief help message and exits.

=item B<--manual>,B<--man>

View application manual

=back

=head1  Commands


=head2 checkout, co, c

	Checkout repositories, set remotes.

=head2  sync|s 

	Sync repositories

=head2  reset|r
	
	Re-configure projects

=head2  check

	Check projects status

=head2  dump
	
	Dump raw datas

=head3  SYNOPSIS
	
	dump [options] [queries]

=head3  OPTIONS

=over 15

=item B<--dump-target>

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

=back

=head2 query

=head3 SYNOPSIS

	query [options] [queries]

=head3 OPTIONS

=item B<--property>
	
	Specify property for quering

=head2 list

	List projects

=head2 reset-config

	Reset .git/config and .git/refs/remotes

=head2 pull

	Pull repository to local repository.

=head2 push

	Push local repository to remotes

=head3 SYNOPSIS

	push [options] [queries]

=head3 OPTIONS

=item B<--remotes>
	
	Specicy remotes for pushing
	
=back	

=head2 config

	Re-configure local repositories

=head2 exec

Execute commands in local reposotiry

=head3 SYNOPSIS

	exec [options] [queries]

=head3 OPTIONS

=item B<--commands>
	
	Specify commands for executing

=back

=head1  FILES

=item B<./.PROJECTS>

Default projects definition file

=back

=head1 PROJECTS FILE FORMAT

	use MyPlace::IniExt;

=head1  DESCRIPTION

Repositories manager, supporting git, svn and mercurial

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
	
	2011-12-06	xiaoranzzz	<xiaoranzzz@myplace.hell>
		
		* Treat first program argument as sub command, clean up options.
		* Update manual
		* Rename actions.
		* version 2.200

	2011-12-12	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* Read query from ".git/config" or ".reposman"
		* Add action "reset-target"
		* version 2.201

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut

#       vim:filetype=perl
