#!/bin/bash

SHELLDIR=$(dirname $(readlink -f $0))
source $SHELLDIR/config.sh

VIMEXECDIR=$(dirname $(dirname $(readlink -f $0)))/vim
EXPECTDIR=$(dirname $(dirname $(readlink -f $0)))/expect
THISSESSIONDIR="$SESSIONDIR/$1"

if [ -e "$FAILDIR/$1" ]; then
    echo "Failed to compile $1 on a prior attempt"
    exit 0
fi

if [[ "$(docker images -q vimrc-test/env-$1 2> /dev/null)" == "" ]]; then
    $SHELLDIR/buildimage.sh $1
fi

if [[ "$(docker images -q vimrc-test/env-$1 2> /dev/null)" == "" ]]; then
    touch $FAILDIR/$1
    echo "Failed to compile $1"
    exit 0
fi

mkdir -p $THISSESSIONDIR

docker run \
--user $(id -u):$(id -g) \
--mount type=bind,source=$SHELLDIR,target=/etc/vimrc-test/sh \
--mount type=bind,source=$VIMEXECDIR,target=/etc/vimrc-test/vim-exec \
--mount type=bind,source=$2,target=/etc/vimrc-test/vimrc \
--mount type=bind,source=$EXPECTDIR,target=/etc/vimrc-test/expect \
--mount type=bind,source=$THISSESSIONDIR,target=/etc/vimrc-test/session \
-it --rm \
-e COLUMNS=$COLUMNS -e LINES=$LINES \
vimrc-test/env-$1 \
/etc/vimrc-test/sh/c-use.sh
