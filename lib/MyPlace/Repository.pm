#!/usr/bin/perl -w
package MyPlace::Repository;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
my %command = (
	'git' => ['git'],
	'svn' => ['svn'],
	'hg' => ['hg','-v'],
);
use MyPlace::Script::Message;

my @git=qw/git/;

sub run_cmd {
	my $self = shift;
	app_message(join(" ",@_),"\n");
	return system(@_) == 0;
}

sub git_push {
	my $self = shift;
	return app_error('Nowhere to push!',"\n") unless($self->{'push'});
	my @prepend = $_[0] ? @{$_[0]} : ();
	my @append = $_[1] ? @{$_[1]} : ();
	return run_cmd(@{$command{git}},@prepend,$self->{'push'},@append);
	
}
sub set_url {
	my $self = shift;
	my $push = shift || $self->{push} || $self->{url};
	return unless($push);
	my $pull = shift || $self->{pull} || $push;
	my $type = shift || $self->{type} || 'git';
	my $host = shift;
	if(!$host) {
		$host = url_get_domain($push);
	}
	$self->{push} = $push;
	$self->{pull} = $pull;
	$self->{type} = $type;
	$self->{host} = $host;
	return $self;
}

sub new {
	my $class = shift;
	my $self =  bless {type=>'git',@_},$class;
	if($self->{url}) {
		$self->set_url($self->{url});
	}
	elsif($self->{push}) {
		$self->set_url($self->{push});
	}
	return $self;
}
#util funtions
sub url_get_domain {
	my $url = shift;
	if($url =~ m/.*?([^\/\\:@\.]+)\.(?:org|com|net|\.cn)/) {
		return $1;
	}
	else {
		return 'no_name';
	}
}
1;

__END__
=pod

=head1  NAME

MyPlace::Repository - PERL Module

=head1  SYNOPSIS

use MyPlace::Repository;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2011-12-05 14:59  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>


# vim:filetype=perl
