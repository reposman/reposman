#!/bin/sh
find . -type f -wholename '*/refs' -or -wholename '*/HEAD' -or -wholename '*/refs/heads/master' | grep -v '/.git' | xargs -l1 git add -v --force -- 
