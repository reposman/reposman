#!/usr/bin/perl -w
package MyPlace::Reposman::Projects;
use strict;
use warnings;

sub new {
	my $class = shift;
	return bless {
		'config'=>{},
		'maps'=>{},
		'hosts'=>{},
		'projects'=>{},
		'data'=>{},
		@_
		},$class;
	}
sub get_raw {
	return $_[0]->{data};
}
sub get_config {
	my $self = shift;
	return $self->{config};
}
sub get_maps {
	my $self = shift;
	return $self->{maps};
}
sub get_hosts {
	my $self = shift;
	return $self->{hosts};
}
sub get_projects {
	my $self = shift;
	return $self->{projects};
}
sub get_repos {
	my $self = shift;
	if($self->{repos}) {
		return $self->{repos};
	}
	my $projects = $self->{projects};
	my %repos;
	foreach(keys %{$projects}) {
		$repos{$_} = $self->new_repo($_,$projects->{$_});
		
	}
	$self->{repos} = \%repos;
	return \%repos;
}

sub get_names {
	my $self = shift;
	my $projects = $self->get_projects();
	return keys %{$projects};
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

sub query_repos {
	my $self = shift;
	my @query = shift;
	my $projects = $self->{projects};
	my @names;
	my @repos;
	foreach my $query (@query) {
		my ($exp,$target) = parse_query($query);
		next unless($exp);
		my $found;
		foreach(keys %{$projects}) {
			if(($exp eq $_) || ($projects->{$_}->{name} eq $exp)) {
				push @names,[$_,$target];
				$found = 1;
				last;
			}
		}
		next if($found);
		foreach(keys %{$projects}) {
			if(($_ =~ m/$exp/) || ($projects->{$_}->{name} =~ m/$exp/)) {
				push @names, [$_,$target];
			}
		}
	}	
	if($self->{repos}) {
		foreach(@names) {
			my $repo = $self->{repos}->{$_->[0]};
			if($repo) {
				$repo = modify_repo_target($repo,$_->[1]);
				push @repos,$repo;
			}
		}
	}
	else {
		foreach(@names) {
			my $repo = $self->new_repo($_->[0],$projects->{$_->[0]});
			if($repo) {
				$repo = modify_repo_target($repo,$_->[1]);
				push @repos,$repo;
			}

		}
	}
	return @repos;
}


sub from_file {
	my $self = shift;
	my $file = shift;
	open FI,'<',$file or return undef;
	my @data = <FI>;
	close FI;
	return $self->from_strings(@data);
}

sub from_strings {
	my $self = shift;
	my %CONFIG;
	my %MAPS;
	my %HOSTS;
	my %PROJECTS;
	require MyPlace::IniExt;
	my %DATA = MyPlace::IniExt::parse_strings(@_);
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
			$PROJECTS{$_}->{name} = $_ unless($PROJECTS{$_}->{name});
		}
	}
	#if(%MAPS) {
	#	foreach (keys %MAPS) {
	#		$CONFIG{$_}->{maps} = $MAPS{$_};
	#	}
	#}
	$self->{data} = \%DATA;
	$self->{config} = \%CONFIG;
	$self->{maps} = \%MAPS;
	$self->{hosts} = \%HOSTS;
	$self->{projects} = \%PROJECTS;
	$self->{repos} = undef;
	return \%CONFIG,\%MAPS,\%HOSTS,\%PROJECTS;
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
	if($url and $id) {
		$url =~ s/:\/\//:\/\/$id\@/;
	}
    return $url;
}

sub parse_url {
	my $self = shift;
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
		$host = $self->{hosts}->{$1};
		$service = $2;
		$entry = $3;
	}
	elsif($template =~ m/^\s*([^\/]+)\/(.*?)\s*$/) {
		$host = $self->{hosts}->{$1};
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

sub new_repo {
    #my ($query_name,@repo_data) = @_;
	my $self = shift;
	my $name = shift;
	my $project = shift;
	my %r;
	$project = {'local'=>'local.git/'} unless($project);
    $r{shortname} = $name ? $name : $project->{shortname};
	$r{name} = $project->{name} ? $project->{name} : $r{shortname};
	$r{localname} = $project->{localname} ? $project->{localname} : $r{name};
	foreach(keys %{$self->{maps}->{localname}}) {
		$r{localname} =~ s/$_/$self->{maps}->{localname}->{$_}/g;
	}
	foreach(qw/user email author username type checkout/) {
		$r{$_} = $project->{$_} ? $project->{$_} : $self->{config}->{$_};
	}
	$r{target} = $r{checkout} || $name;
	if($r{target} =~ m/\/$/) {
		$r{target} .= $name;
	}
	foreach my $url_type (qw/local source mirror mirrors_1 mirrors_2 mirrors_3 mirrors_4 mirrors_5 mirrors_6/) {
		my $key = "$url_type";
		if($project->{$key}) {
			my $url = $self->parse_url($r{name},$project->{$key},\%r);
			push @{$r{$url->{type}}},$url;
		}
	}
	if($project->{"mirrors"}) {
		foreach(@{$project->{"mirrors"}}) {
			my $url = $self->parse_url($r{name},$_,\%r);
			push @{$r{$url->{type}}},$url;
		}
	}
    return \%r;
}
1;

__END__
=pod

=head1  NAME

MyPlace::Reposman::Projects - PERL Module

=head1  SYNOPSIS

use MyPlace::Reposman::Projects;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2011-12-05 22:00  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.

		* copy codes form reposman.pl

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>


# vim:filetype=perl

