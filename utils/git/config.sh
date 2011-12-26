#!/bin/sh

function run {
	echo "$@"
	$@
}

gitc="git config" 
run "$gitc pack.packSizeLimit 4m"
run "$gitc gc.auto 0"
if [ -z "$1" ] ; then
	true
elif [ "-b" == "$1" ] ; then
	run "$gitc core.compression 0"
	run "$gitc pack.compression 0"
fi
