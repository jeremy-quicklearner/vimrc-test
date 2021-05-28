#!/bin/bash
set -e

if ! [ -e "/etc/vimrc-test-isbuild" ]; then
    echo "Must run from inside the vimrc-test/build container"
    exit 1
fi

if ! [ -n "$1" ]; then
    echo "Must supply valid Vim tag or branch to build"
    exit 1
fi

if ! [ -n "/usr/local/vim-$2" ]; then
    echo "Must supply valid install directory for build"
    exit 1
fi

chown $(id -u):$(id -g) /etc/vimrc-test/vim-src
chown $(id -u):$(id -g) /usr/local/vim-testbed
chown $(id -u):$(id -g) /usr/local/vim-subject

cd /etc/vimrc-test/vim-src

# In case the last build changed source-controlled files
make distclean || RETVAL=$?
git reset --hard
git clean -fd

git fetch --all --tags

git checkout $1

make distclean || RETVAL=$?
git reset --hard
git clean -fd

./configure --prefix=/usr/local/vim-$2 --exec-prefix=/usr/local/vim-$2

make

make install
