#!/usr/bin/perl -w
# $Id$
use strict;
our $VERSION = '2.000';
BEGIN
{
    my $PROGRAM_DIR = $0;
    $PROGRAM_DIR =~ s/[^\/\\]+$//;
    $PROGRAM_DIR = "./" unless($PROGRAM_DIR);
    unshift @INC, 
        map "$PROGRAM_DIR$_",qw{modules lib ../modules ..lib};
}
my %OPTS;
my @OPTIONS = qw/help|h|? manual|m test|t project|p debug dump|d dump-projects|dp dump-config|dc dump-data|dd sync|s sync-all|sa checkout|co|c file|f:s login|nu no-local fetch-all no-remote reset-config to-local force to-remote config-local mirror list query:s dump-hosts|dh dump-target|dt dump-maps|dm dump-all|da branch|b:s exec-local|el:s append|aa:s prepend|pa:s/;
if(@ARGV)
{
    require Getopt::Long;
    Getopt::Long::GetOptions(\%OPTS,@OPTIONS);
}
else {
    $OPTS{help} = 1;
}

#use MyPlace::Repository;

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
	if($first_arg and $first_arg =~ m/^(help|manual|test|project|dump|dump-config|dump-data|check|list|pull|reset|clone|sync|checkout|to-local|to-remote|config-local|query|list|dump-target|dump-hosts|dump-maps|dump-all)$/) {
		$OPTS{$first_arg} = 1;
	}
	else {
		unshift @ARGV,$first_arg;
		$OPTS{sync} = 1;
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
my @HG = qw/hg -v/;
my @GIT = qw/git/;
my @SVN = qw/svn/;
my %DATA;
my %REPOS;

my %project;
my %sub_project;

my %CONFIG;
my %PROJECTS;
my %HOSTS;
my %MAPS;

sub parse_project_data {
	require MyPlace::IniExt;
	%DATA = MyPlace::IniExt::parse_strings(@_);
	no warnings;
	my $config_key = $MyPlace::IniExt::DEFINITION;
	foreach(keys %DATA) {
		if($_ eq $config_key) {
			#foreach my $key (keys %{$DATA{$_}}) {
			#	$CONFIG{$key} = $DATA{$_}->{$key};
			#}
			%CONFIG = (%CONFIG,%{$DATA{$_}});
		}
		elsif($_ =~ m/^host\.(.+)$/) {
			$HOSTS{$1} = $DATA{$_};
		}
		elsif($_ =~ m/^map\.(.+)$/) {
			$MAPS{$1} = $DATA{$_};
		}
		elsif($_ =~ m/^type\.(.+)$/) {
			$CONFIG{$1} = $DATA{$_};
		}
		else {
			$PROJECTS{$_} = $DATA{$_};
		}
	}
	#if(%MAPS) {
	#	foreach (keys %MAPS) {
	#		$CONFIG{$_}->{maps} = $MAPS{$_};
	#	}
	#}
	return \%CONFIG,\%MAPS,\%HOSTS,\%PROJECTS;
}
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
	return $name,$PROJECTS{$name};
}


sub translate_url {
    my $url = shift;
    my $path = shift;
	my $id = shift;
	my $root;
	my $leaf;
	if($path =~ m/^([^\/]+)\/(.+)$/) {
		$root = $1;
		$leaf = $2;
	}
	else {
		$root = $path;
		$leaf = undef;
	}
	if($leaf) {
		if($url =~ m/#2/) {
			$url =~ s/#1/$root/g;
			$url =~ s/#2[!]?/$leaf/g;
		}
		else {
			$url =~ s/#1/$path/g;
		}
	}
	else {
		$url =~ s/#1/$root/g;
		$url =~ s/#2!/$root/g;
		$url =~ s/[\/\.\-]?#2//g;
	}
    #$url =~ s/\/+$//;
	#$url =~ s/\.{2,}([^\/]+)/\.$1/g;
	if($url and $OPTS{'login'}) {
		$url =~ s/:\/\//:\/\/$id\@/;
	}
    return $url;
}
sub parse_url {
	my $name = shift;
	my $template = shift;
	my $project = shift;
	next unless($template);
	#if($template =~ m/\/$/) {
	#	$template = $template ."$name"; 
	#}
	if($template =~ m/^(.+)\/#([^#]+)#$/) {
		if($project->{$2}) {
			$template = "$1/$project->{$2}";
		}
	}
	my $user = $project->{user};
	if($template =~ m/^([^\/\@]+)\@(.+)$/) {
		$template = $2;
		$user = $1;
	}
	my $host;
	my $service;
	my $entry;
	if($template =~ m/^\s*([^\.\/]+)\.([^\/]+)\/(.*?)\s*$/) {
		$host = $HOSTS{$1};
		$service = $2;
		$entry = $3;
	}
	elsif($template =~ m/^\s*([^\/]+)\/(.*?)\s*$/) {
		$host = $HOSTS{$1};
		$entry = "";
	}
	if($template =~ m/\/$/) {
		if(ref $host and $host->{map} and $host->{map} eq 'localname') {
			$entry .= $project->{localname};
		}
		else {
			$entry .= $name;
		}
	}
	my ($push,$pull,$type);
	if($host) {
		if(ref $host->{$service} and $host->{$service}->{write}) {
			$push = translate_url($host->{$service}->{write},$entry,$user);
		}
		elsif($host->{write}) {
			$push = translate_url($host->{write},$entry,$user);
		}
		elsif($host->{$service}) {
			$push = translate_url($host->{$service},$entry,$user);
		}

		if(ref $host->{$service} and $host->{$service}->{read}) {
			$pull = translate_url($host->{$service}->{read},$entry,$user);
		}
		elsif($host->{read}) {
			$pull = translate_url($host->{read},$entry,$user);
		}
		elsif($push) {
			$pull = $push;
		}

		$push = $pull if(!$push);
		$type = $host->{$service}->{type} if(ref $host->{$service});
		$type = $service || $host->{type} unless($type); 
	}

	if(!$push) {
		$push = $pull =  translate_url($template,$entry,$user);
	}
	if(!$type) {
		$type = $project->{type};
	}
	return {'push'=>$push,'pull'=>$pull,'user'=>$user,'type'=>$type};
}

sub get_repos {
	my $query = shift;
	my @repos;
	my $match = 0;
	my ($query_str,$new_target) = parse_query($query);
	foreach my $key (qw/name shortname localname/) {
		foreach my $name (keys %REPOS) {
			if($REPOS{$name}->{$key} eq $query_str) {
				push @repos,$REPOS{$name};
				$match = 1;
			}
		}
		last if($match);
	}
	unless($match) {
	foreach my $key (qw/name shortname localname/) {
		foreach my $name (keys %REPOS) {
			if($REPOS{$name}->{$key} =~ $query_str) {
				push @repos,$REPOS{$name};
				$match = 1;
			}
		}
		last if($match);
	}
	}
	if($new_target) {
		foreach(@repos) {
			modify_repo_target($_,$new_target);
		}
	}
	return @repos;
}
sub modify_repo_target {
	my $repo = shift;
	my $target = shift;
	return $repo unless($target);
	$repo->{_target} = $repo->{target};
	if($target =~ m/\/$/) {
		$target .= $repo->{name};
	}
	$repo->{target} = $target;
	return $repo;
}
sub get_repo {
    #my ($query_name,@repo_data) = @_;
	my $query_name = shift;
	my $project = shift;
	my %r;
	$project = {'local'=>'local.git/'} unless($project);
	my ($name,$new_target) = parse_query($query_name);
    $r{shortname} = $name ? $name : $project->{shortname};
	$r{name} = $project->{name} ? $project->{name} : $r{shortname};
	$r{localname} = $project->{localname} ? $project->{localname} : $r{name};
	foreach(keys %{$MAPS{localname}}) {
		$r{localname} =~ s/$_/$MAPS{localname}->{$_}/g;
	}
	foreach(qw/user email author username type checkout/) {
		$r{$_} = $project->{$_} ? $project->{$_} : $CONFIG{$_};
	}
	my $target = $r{checkout};
	$target = $name unless($target);
	if($new_target) {
		$r{target} = $new_target;
		$r{_target} = $target;
	}
	else {
		$r{target} = $target;
	}
	if($r{target} =~ m/\/$/) {
		$r{target} .= $name;
	}
	foreach my $url_type (qw/local source mirror mirrors_1 mirrors_2 mirrors_3 mirrors_4 mirrors_5 mirrors_6/) {
		my $key = "$url_type";
		if($project->{$key}) {
			my $url = parse_url($r{name},$project->{$key},\%r);
			push @{$r{$url->{type}}},$url;
		}
	}
	if($project->{"mirrors"}) {
		foreach(@{$project->{"mirrors"}}) {
			my $url = parse_url($r{name},$_,\%r);
			push @{$r{$url->{type}}},$url;
		}
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
my $PROGRAM_DIR = $0;
$PROGRAM_DIR =~ s/[^\/\\]+$//;
my $cwd = getcwd();
my $PROJECT_FILE;
if($OPTS{file}) {
	$PROJECT_FILE=$OPTS{file};
}
else {
	foreach my $fn (".PROJECTS","~/.PROJECTS","~/.reposman/PROJECTS","/etc/reposman/PROJECTS") {
	    if(-f $fn) {
	        $PROJECT_FILE = $fn;
	        last;
	    }
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


my $total = scalar(keys %PROJECTS);
print STDERR "$total", $total > 1 ? " projects" : " project", ".\n";

foreach(keys %PROJECTS) {
	my ($name,$pdata) =  get_project_data($_);
	$REPOS{$name} = get_repo($_,$pdata);
}

my @query = @ARGV ? @ARGV : (keys %PROJECTS);

my @targets;
if(@ARGV) {
	foreach(@query) {
		push @targets,get_repos($_);
	}
}
else {
	@targets = values %REPOS;
}

if($OPTS{'dump-all'}) {
	foreach (qw/
		dump
		dump-data 
		dump-config
		dump-maps
		dump-hosts
		dump-projects
	/) {
		$OPTS{$_} = 1;
	}
}
if($OPTS{'dump'}) {
    $OPTS{'dump-target'} = 1;
}

use Data::Dumper;
print Data::Dumper->Dump([\%DATA],["*DATA"]) if($OPTS{'dump-data'});
print Data::Dumper->Dump([\%CONFIG],["*CONFIG"]) if($OPTS{'dump-config'});
print Data::Dumper->Dump([\%MAPS],["*MAPS"]) if($OPTS{'dump-maps'});
print Data::Dumper->Dump([\%HOSTS],["*HOSTS"]) if($OPTS{'dump-hosts'});
print Data::Dumper->Dump([\%PROJECTS],["*PROJECTS"]) if($OPTS{'dump-projects'});
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

=item B<-p>,B<--project>

Target and define project from command line

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
		* update program and module to reflect format changing;
		* version 2.000

	2011-12-01	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add option --branch|-b
	
	2011-12-05	xiaoranzzz	<xiaoranzzz@myplace.hell>

		* add options --exec-locak, --append, --prepend

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut

#       vim:filetype=perl
