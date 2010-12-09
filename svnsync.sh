#!/bin/sh
echo svnsync sync file://`pwd`/svn
exec svnsync sync file://`pwd`/svn

