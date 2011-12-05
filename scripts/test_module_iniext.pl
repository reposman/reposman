#!/usr/bin/perl -w
use strict;

require "lib/MyPlace/IniExt.pm";
use Data::Dumper;

my %data = MyPlace::IniExt::parse_file(".PROJECTS");

print Data::Dumper->Dump([\%data],[qw/*data/]),"\n";
