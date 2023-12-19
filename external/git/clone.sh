#!/bin/sh

# solution plucked from http://stackoverflow.com/questions/59895
SOURCE="$0"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  case $SOURCE in
    "/"*) true ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

if [ ! -f "$DIR/clone.sh" ] || [ -h "$DIR/clone.sh" ]; then
  >&2 echo 'Could not resolve source directory, make sure to execute the source file instead of sourcing it'
  exit 1
fi

git clone https://luajit.org/git/luajit-2.0.git "$DIR/luajit"
git clone --depth 1 https://github.com/letoram/openal.git "$DIR/openal"
git clone --depth 1 https://github.com/libuvc/libuvc.git "$DIR/libuvc"
git clone --depth 1 https://github.com/wolfpld/tracy.git "$DIR/tracy"
