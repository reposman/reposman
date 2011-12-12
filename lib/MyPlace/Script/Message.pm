#!/usr/bin/perl
package MyPlace::Script::Message;
use Term::ANSIColor;
BEGIN {
    use Exporter ();
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&app_ok &app_message &app_error &app_warning &app_abort &color_print);
    @EXPORT_OK      = map "print_$_",(qw/red blue yellow white black cyan green/);
}


my $id = $0;
$id =~ s/^.*\///g;
my $prefix="\r$id> ";

my %CHANNEL = (
    "message"=>"cyan",
    "message2"=>"green",
    "ok"=>"green",
    "warning"=>"yellow",
    "warn"=>"yellow",
    "error"=>"red",
    "abort"=>"red"
);

sub color_print($$@) {
    my $out=shift;
    my $ref=ref $out ? $out : \$out;
    if(!((ref $ref) eq "GLOB")) {
        $ref=*STDERR;
        unshift @_,$out;
    }
    my $color=shift;
    if($ENV{OS} and $ENV{OS} =~ /windows/i) {
        print STDERR @_;
    }
    else {
        print $ref color($color),@_,color('reset') if(@_);
    }
}

#sub app_error {
#    print STDERR $prefix;
#    color_print *STDERR,'red',@_;
#}
#
#sub app_message {
#    print STDERR $prefix,@_;
#}
#sub app_message2 {
#    print STDERR $prefix,color('green'),@_,color('reset');
#    color_print *STDERR,'green',@_;
#}
#}
#sub app_warning {
#    print STDERR $prefix;
#    color_print *STDERR,'yellow',@_;
#}

sub app_abort {
    &app_error(@_);
    exit $?;
}

sub AUTOLOAD {
    if($ENV{OS} and $ENV{OS} =~ /windows/i) {
        print STDERR @_;
    }
    elsif($AUTOLOAD =~ /::(?:app|print)_([\w\d_]+)$/) {
        my $channel = $CHANNEL{$1} || $1 ; #'reset';
        my $flag = shift(@_);
        if($flag eq '--no-prefix') {
            print STDERR color($channel),@_,color('reset');
        }
        else {
            print STDERR $prefix,color($channel),$flag,@_,color('reset');
        }
        return 1;
    }
    return undef;
}
return 1;
