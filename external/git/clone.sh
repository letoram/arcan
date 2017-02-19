#!/bin/bash

# solution plucked from http://stackoverflow.com/questions/59895
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

git clone http://luajit.org/git/luajit-2.0.git "$DIR/luajit"
git clone git://git.sv.nongnu.org/freetype/freetype2.git "$DIR/freetype"

# reason we're doing this bullshit here is to protect against future
# al breaks, and deal with the bugfest from ExternalProject_Add when it
# comes to build states, cleanup, patching and so on.
git clone git://repo.or.cz/openal-soft.git "$DIR/openal"
git -c user.name="me" -c user.email="me@my.org" -C "$DIR/openal" am -3 --ignore-space-change --ignore-whitespace ../openal.patch
git -c user.name="me" -c user.email="me@my.org" -C "$DIR/openal" tag patched_al
