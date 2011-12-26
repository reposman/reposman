#!/bin/sh
for i in afun dirtyword dirtybase repos ; do 
	git --bare init $i/git
	git init $i
done
