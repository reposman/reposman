#!/bin/sh
msg="$*"
d=`dirname "$0"`

#svnadmin pack svn
#git --bare --git-dir=git gc

[ -d "git" ] && git add git
[ -d "svn" ] && git add svn

perl "$d/s_generate_log.pl"

if [ -f "repo.log.bak" ] ; then
	cp -av "repo.log.bak" "repo.log"
elif [ -f "repo.log" ] ; then
	cp -av "repo.log" "repo.log.bak"
else
	touch repo.log
	touch repo.log.bak
fi


gc="git commit"
if [ -n "$msg" ] ; then
	gc="$gc -am "${msg}""
else
	if [ -f "info" ] ; then
		cat info >>repo.log
	fi
	if [ -f "status" ] ; then
		gc="$gc -aF status"
	else
		gc="$gc -a"
	fi
fi
echo $gc
if $gc ; then
	echo "git commit OK"
else
	echo "git commit failed"
	if [ -f "repo.log.bak" ] ; then
		cp -av "repo.log.bak" "repo.log"
	fi
	exit 1
fi

#if git svn dcommit ; then
#	echo "[OK]"
#	rm status info repo.log.bak
#else
#	echo "git svn dcommit failed"
	#git reset HEAD^
	#if [ -f "repo.log.bak" ] ; then
	#	cp -av "repo.log.bak" "repo.log"
	#fi
	#rm status info repo.log.bak
#	exit 1
#fi
#exit 0
