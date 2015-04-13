#!/bin/bash

# solution plucked from http://stackoverflow.com/questions/59895
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

git clone http://luajit.org/git/luajit-2.0.git $DIR/luajit
git clone git://git.sv.nongnu.org/freetype/freetype2.git $DIR/freetype
git clone https://www.github.com/mirror/openal-soft.git $DIR/openal
