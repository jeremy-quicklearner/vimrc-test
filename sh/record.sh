#!/bin/bash

SHELLDIR=$(dirname $(readlink -f $0))
VIMEXECDIR=$(dirname $(dirname $(readlink -f $0)))/vim
EXPECTDIR=$(dirname $(dirname $(readlink -f $0)))/expect
SESSIONDIR="/etc/vimrc-test/session/record"

if [[ "$(docker images -q vimrc-test/testbed 2> /dev/null)" == "" ]]; then
    # Arbitrarily build v8.2.2366. The testbed will get built as part
    # of that process
    $SHELLDIR/buildimage.sh v8.2.2366
fi

mkdir -p $SESSIONDIR

docker run \
--mount type=bind,source=$SHELLDIR,target=/etc/vimrc-test/sh \
--mount type=bind,source=$VIMEXECDIR,target=/etc/vimrc-test/vim-exec \
--mount type=bind,source=$1,target=/root/vim \
--mount type=bind,source=$EXPECTDIR,target=/etc/vimrc-test/expect \
--mount type=bind,source=$SESSIONDIR,target=/etc/vimrc-test/session \
-it --rm \
-e COLUMNS=$COLUMNS -e LINES=$LINES \
vimrc-test/testbed \
/etc/vimrc-test/sh/c-record.sh

# Give dockerd some extra time to stop the container
sleep 1
