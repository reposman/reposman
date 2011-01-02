#!/usr/bin/perl -w
# $Id$
use strict;
require v5.8.0;
our $VERSION = 'v1.0';

my %OPTS;
my @OPTIONS = qw/help|h|? manual|m test|t project|p debug dump|d dump-config|dc dump-data|dd sync|s sync-all|sa checkout|co|c/;
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
	if($first_arg and $first_arg =~ m/^(help|manual|test|project|dump|dump-config|dump-data|check|list|pull|reset|clone|sync|checkout)$/) {
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
            if($name =~ m/^(?:id|id:.+|authors|user|username|email|s|s:.+|svn|svn:.+|g|g:.+|git|git:.+|h|h:.+|hg|hg:.+)$/) {
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
		next unless(@data);
        my $name = shift @data;
		next unless($name);
        if($data[0] and $data[0] =~ m/.+\/.+/) {
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
	my $id = shift;
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
	$url =~ s/\/\.+/\//g;
	$url =~ s/\.{2,}([^\/]+)/\.$1/g;
	if($url) {
		$url =~ s/:\/\//:\/\/$id\@/;
	}
    return $url;
}
sub parse_url {
	my $name = shift;
	my $template = shift;
	next unless($template);
	my $push = $template;
	if($push =~ m/\/$/) {
		$push = $push ."$name"; 
	}
	my $id = $CONFIG{id};
	my $type = $CONFIG{type};
	if($push =~ m/^([^\/\@]+)\@(.+)$/) {
		$push = $2;
		$id = $1;
	}
	if($push =~ m/^(?:h|h:.+|hg|hg:.+)$/) {
		$type = 'hg';
	}
	elsif($push =~ m/^(?:s:|s:.+|svn|svn:.+)$/) {
		$type = 'svn';
	}
	elsif($push =~ m/^(?:g|g:.+|git|git:.+)$/) {
		$type = 'git';
	}
	my $pull = $push;
	my $remote_name = 'default';
	if($push =~ m/\s*([^:]+):([^:\/]+)\/(.*?)\s*$/) {
		if($CONFIG{"$1:$2:write"} and $CONFIG{"$1:$2:read"}) {
			$push = translate_url($CONFIG{"$1:$2:write"},$3,$id);
			$pull = translate_url($CONFIG{"$1:$2:read"},$3,$id);
			$remote_name = $2;
		}
		elsif($CONFIG{"$1:$2:write"}) {
			$push = translate_url($CONFIG{"$1:$2:write"},$3,$id);
			$remote_name = $2;
		}
		elsif($CONFIG{"$1:$2:read"}) {
			$pull = translate_url($CONFIG{"$1:$2:read"},$3,$id);
			$remote_name = $2;
		}
		elsif($CONFIG{"$1:$2"}) {
			$push = translate_url($CONFIG{"$1:$2"},$3,$id);
			$pull = $push;
			$remote_name = $2;
		}
	}
	return {'push'=>$push,'pull'=>$pull,'id'=>$id,'type'=>$type};
}
sub get_repo {
    my ($query_name,@repo_data) = @_;
    my %r;
	my ($name,$new_target) = parse_query($query_name);
    $r{name} = $name;
	my $target = shift @repo_data;
	$target = $name unless($target);
	if($new_target) {
		$r{target} = $new_target;
		$r{_target} = $target;
	}
	else {
		$r{target} = $target;
	}
	$target = parse_url($name,$r{target});
	if($target) {
		$r{target} = $target->{'push'};
	}
    @repo_data = ("s:local/$name","s:remote/$name",) unless(@repo_data);
	if($OPTS{debug}) {
		print STDERR "debug::get_repo> $name -  ",join("  |",@repo_data),"\n";
	}
	while(@repo_data) {
		my $template = shift @repo_data;
		my $url = parse_url($name,$template);
		if($url) {
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

sub git_push_remote {
    my @remotes;
    open FI,"-|",qw/git remote/;
    while(<FI>) {
        chomp;
        push @remotes,$_ if($_);
    }
    close FI;
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
sub GIT_R {
	my $target = shift;
	return @GIT,'--work-tree',$target,'--git-dir',$target . '/.git';
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

sub git_add_remote {
	my ($repo,$target,@remotes) = @_;
	my %pool;
	foreach(@remotes) {
		my $url = $_->{'push'};
		my $name = unique_name(url_get_domain($url),\%pool);
		$pool{$name} = 1;
		run(GIT_R($target),qw/remote rm/,$name);
		run(GIT_R($target),qw/remote add/,$name,$url);
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
		my $source = shift @{$repo->{git}};
		unless(-d $target) {
			run(@GIT,'clone',$source->{'push'},$target);
		}
		else {
			run(@GIT,"init",$target);
			run(@GIT,"--work-tree",$target,"--git-dir","$target/.git",qw/remote rm origin/);
			run(@GIT,"--work-tree",$target,"--git-dir","$target/.git",qw/remote add origin/,$source->{'push'});
		}
		git_add_remote($repo,$target,@{$repo->{git}});
		run(GIT_R($target),qw/fetch --all/);
		run(GIT_R($target),qw/remote -v/);
		run(GIT_R($target),qw/branch -av/);
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
		run(@GIT,'--bare','clone',$source->{'pull'},$target);
		unless($first_only) {
			foreach(@{$repo->{git}}) {
				run(@GIT,'--bare','--git-dir',$target,'push',$_->{'push'});
			}
		}
	}
	return 1;
}

my $PROGRAM_DIR = $0;
$PROGRAM_DIR =~ s/[^\/\\]+$//;
my $cwd = getcwd();
my $PROJECT_FILE;

foreach my $fn (".PROJECTS","~/.PROJECTS","~/.reposman/PROJECTS","/etc/reposman/PROJECTS") {
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
else {
	die("Invalid action specified!\n");
}

print STDERR "to $action $count ", $count > 1 ? "projects" : "project", " ...\n";
foreach my $query_text (@query) {
        $idx++;
		my ($name,$pdata) = get_project_data($query_text);
        print STDERR "[$idx/$count] $action" . " project [$name]\n";
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

reposman - svn,git,mercurial repositories manager

=head1  SYNOPSIS

reposman [options] [action] [project_name|project_name:target]...
	reposman --sync ffprofile
	reposman sync ffprofile

=head1  OPTIONS

=over 12

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
