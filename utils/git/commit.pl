#!/bin/sh

perl ./generate-log.pl . >README 

git add README
git commit "$@"
