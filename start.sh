#!/bin/sh
svn_repo="http://pl3.projectlocker.com/eotect/gsbridge/svn/trunk"
echo svn export --force "$svn_repo" .
svn export --force "$svn_repo" .
