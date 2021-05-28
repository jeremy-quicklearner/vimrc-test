#!/bin/bash
set -e

if ! [ -e "/etc/vimrc-test-istest" ]; then
    echo "Must run from inside a testbed container"
    exit 1
fi

if ! [ -e "/usr/local/vim-testbed/bin/vim" ]; then
    echo "No Testbed installation found"
    exit 1
fi

if ! [ -e "/usr/local/vim-subject/bin/vim" ]; then
    echo "No Subject installation found"
    exit 1
fi

if ! [ -e "/etc/vimrc-test/vimrc/setup" ]; then
    echo "Vimrc not present"
    exit 1
fi

if ! [ -e "/etc/vimrc-test/expect" ]; then
    echo "No expected state found"
    exit 1
fi

if ! [ -e "/etc/vimrc-test/session" ]; then
    echo "No session directory found"
    exit 1
fi

HOME=/etc/vimrc-test/home

/etc/vimrc-test/vimrc/setup

if ! [ -e ~/.vimrc ]; then
    echo "Vimrc setup failed"
    exit 1
fi

/usr/local/vim-subject/bin/vim -c 'set viminfo='
