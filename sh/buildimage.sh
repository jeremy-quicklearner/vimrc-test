#!/bin/bash
set -e
shopt -s expand_aliases

SHELLDIR=$(dirname $(readlink -f $0))
source $SHELLDIR/config.sh

DOCKERFILEDIR=$(dirname $(dirname $(readlink -f $0)))/docker

mkdir -p $BUILDDIR
mkdir -p $FAILDIR

if ! [ -n "$1" ]; then
    echo "Must supply valid Vim tag or branch to build"
    exit 1
fi

touch $LOCKFILE
exec {FD}<>$LOCKFILE

echo Acquiring Build Lock
flock -x $FD
echo Build Lock acquired

if ! [ -d "$SRCDIR" ] ; then
    git clone https://github.com/vim/vim $SRCDIR
fi

if [[ "$(docker images -q vimrc-test/build 2> /dev/null)" == "" ]]; then
    # Build an image in which to compile Vim ("The Build Container")
    DOCKER_BUILDKIT=1 docker build \
        -t vimrc-test/build \
        -f $DOCKERFILEDIR/build \
        $BUILDDIR
fi

# Function for running things in the build container
alias buildrun='docker run \
--user $(id -u):$(id -g) \
--mount type=bind,source=$SHELLDIR,target=/etc/vimrc-test/sh \
--mount type=bind,source=$SRCDIR,target=/etc/vimrc-test/vim-src \
--mount type=bind,source=$BUILDDIR/testbed,target=/usr/local/vim-testbed \
--mount type=bind,source=$BUILDDIR/$1,target=/usr/local/vim-subject \
-i -t --rm \
-e COLUMNS=$COLUMNS -e LINES=$LINES \
vimrc-test/build'

mkdir -p $BUILDDIR/$1
mkdir -p $BUILDDIR/testbed

if [[ "$(docker images -q vimrc-test/testbed 2> /dev/null)" == "" ]]; then
    # Use the build container to compile latest Vim for use as a testbed
    buildrun /etc/vimrc-test/sh/c-build.sh master testbed

    # Build image that has the testbed Vim in it
    DOCKER_BUILDKIT=1 docker build \
        -t vimrc-test/testbed \
        -f $DOCKERFILEDIR/testbed \
        $BUILDDIR

    rm -rf $BUILDDIR/testbed/*
fi

# Use the build container to compile desired Vim version for use as subject
RETVAL=0
buildrun /etc/vimrc-test/sh/c-build.sh $1 subject || RETVAL=$?
if (( $RETVAL )); then
    rm -rf $BUILDDIR/$1
    exit 0
fi


# Build an image that has both testbed and subject Vims
DOCKER_BUILDKIT=1 docker build \
    -t vimrc-test/env-$1 \
    -f $DOCKERFILEDIR/env \
    --build-arg SUBJECT=$1 \
    $BUILDDIR

# Remove the build artefacts
rm -rf $BUILDDIR/$1
