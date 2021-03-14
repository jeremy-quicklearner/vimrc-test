#!/bin/bash

ETCDIR="/etc/vimrc-test"
BUILDDIR="$ETCDIR/vimbuild"
SHELLDIR=$(dirname $(readlink -f $0))
VIMEXECDIR=$(dirname $(dirname $(readlink -f $0)))/vim
EXPECTDIR=$(dirname $(dirname $(readlink -f $0)))/expect
SESSIONDIR="/etc/vimrc-test/session/$1"

if [ -e "$BUILDDIR/failed-$1" ]; then
    echo "Failed to compile $1 on a prior attempt"
    exit 0
fi

if [[ "$(docker images -q vimrc-test/env-$1 2> /dev/null)" == "" ]]; then
    $SHELLDIR/buildimage.sh $1
fi

if [[ "$(docker images -q vimrc-test/env-$1 2> /dev/null)" == "" ]]; then
    touch $BUILDDIR/failed-$1
    echo "Failed to compile $1"
    exit 0
fi

mkdir -p $SESSIONDIR

docker run \
--mount type=bind,source=$SHELLDIR,target=/etc/vimrc-test/sh \
--mount type=bind,source=$VIMEXECDIR,target=/etc/vimrc-test/vim-exec \
--mount type=bind,source=$2,target=/root/vim \
--mount type=bind,source=$EXPECTDIR,target=/etc/vimrc-test/expect \
--mount type=bind,source=$SESSIONDIR,target=/etc/vimrc-test/session \
-it --rm \
-e COLUMNS=$COLUMNS -e LINES=$LINES \
vimrc-test/env-$1 \
/etc/vimrc-test/sh/c-use.sh
