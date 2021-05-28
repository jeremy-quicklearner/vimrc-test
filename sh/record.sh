#!/bin/bash

SHELLDIR=$(dirname $(readlink -f $0))
source $SHELLDIR/config.sh

VIMEXECDIR=$(dirname $(dirname $(readlink -f $0)))/vim
EXPECTDIR=$(dirname $(dirname $(readlink -f $0)))/expect
THISSESSIONDIR="$SESSIONDIR/record"

if [[ "$(docker images -q vimrc-test/testbed 2> /dev/null)" == "" ]]; then
    # Arbitrarily build v8.2.2366. The testbed will get built as part
    # of that process
    $SHELLDIR/buildimage.sh v8.2.2366
fi

mkdir -p $THISSESSIONDIR

docker run \
--user $(id -u):$(id -g) \
--mount type=bind,source=$SHELLDIR,target=/etc/vimrc-test/sh \
--mount type=bind,source=$VIMEXECDIR,target=/etc/vimrc-test/vim-exec \
--mount type=bind,source=$1,target=/etc/vimrc-test/vimrc \
--mount type=bind,source=$EXPECTDIR,target=/etc/vimrc-test/expect \
--mount type=bind,source=$THISSESSIONDIR,target=/etc/vimrc-test/session \
-it --rm \
-e COLUMNS=$COLUMNS -e LINES=$LINES \
vimrc-test/testbed \
/etc/vimrc-test/sh/c-record.sh

# Give dockerd some extra time to stop the container
sleep 1
