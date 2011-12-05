#!/bin/sh
cmd=$1
shift
svn $cmd file://`pwd`/svn "$@"
