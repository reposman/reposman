#!/bin/sh
script="reposman push"
logfile="sync-repos.log"
{
echo " "
echo "========================================================" 
date +"[%Y-%m-%d %H:%M:%S] Started:"
cwd=`pwd`;
while [ -n "$1" ] ; do
	if [ -f "$1/.reposman" ] ; then
		cd "$1"
		echo [$1] $script
		$script
		cd -- "$cwd";
	else
		echo $script -- "$1" 	
		$script -- "$1" 	
	fi
	shift
	[ -n "$1" ] && echo " "
done
date +"[%Y-%m-%d %H:%M:%S] Finished."
echo .
echo " "
} | tee -a "$logfile"
git add -- "$logfile"
