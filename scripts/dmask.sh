#!/bin/sh
if [ -n "$*" ] ; then
	exec base64 -d "$@"
fi

maskfile=
if [ -f mask ] ; then
	maskfile=mask
elif [ -f workspace/mask ] ; then
	maskfile=workspace/mask
elif [ -f ../mask ] ; then
	maskfile=../mask
elif [ -f ../workspace/mask ] ; then
	maskfile=../workspace/mask
elif [ -f ~/mask ] ; then
	maskfile=~/mask
elif [ -f ~/.mask ] ; then
	maskfile=~/.mask
elif [ -f /myplace/workspace/mask ] ; then
	maskfile=/myplace/workspace/mask
elif [ -f /myplace/mask ] ; then
	maskfile=/myplace/mask
elif [ -f ~/myplace/mask ] ; then
	maskfile=~/myplace/mask
elif [ -f ~/myplace/workspace/mask ] ; then
	maskfile=~/myplace/workspace/mask
elif [ -f ~/workspace/mask ] ; then
	maskfile=~/workspace/mask
fi

if [ -n "$maskfile" ] ; then
	echo "[$maskfile]"
	base64 -d "$maskfile"
else
	base64 -d "$@"
fi
