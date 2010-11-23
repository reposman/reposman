#!/bin/sh
NAME="repos"
SOURCE="data home *.git"


CMD="sudo tar"
[ "$UID" = "0" ] && CMD=tar
ARGS="-cvf"

EXT=".tar.7z"
TARGET="${NAME}_$(date +%Y-%m-%d_%H-%M-%S)${EXT}"
EXCLUDE="${NAME}_*${EXT}"

#echo $CMD $ARGS "$TARGET" --exclude="$EXCLUDE" $SOURCE
#$CMD $ARGS "$TARGET" --exclude="$EXCLUDE" $SOURCE

echo $CMD -cvf - --exclude="$EXCLUDE" $SOURCE \| 7z a -mx9 -p -si "$TARGET"
$CMD -cvf - --exclude="$EXCLUDE" $SOURCE | 7z a -mx9 -p -si "$TARGET"
