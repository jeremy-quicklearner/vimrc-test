#!/bin/bash

# Test courses:
# ALLVIM - Test against every supported version of Vim
# ALL0 - Test against supported versions ending in 0
# ALL00 - Test against supported versions ending in 00
# ALL000 - Test against supported versions ending in 000
# MINMAX - Test versions between a minimum and a maximum (inclusive)
# MINMAX0 - Test versions ending in 0 between a minimum and a maximum (inclusive)
# MINMAX00 - Test versions ending in 00 between a minimum and a maximum (inclusive)
export COURSE=ALL00
export COURSE_MIN=v7.3.1058
export COURSE_MAX=v7.3.1160

# Number of threads to use in local run
export NUM_THREADS=128

# Vim source repo goes here
export SRCDIR="$(dirname $(dirname $(readlink -f $0)))/tmp/vim-src"

# Vim build failure notes go here
export FAILDIR="$(dirname $(dirname $(readlink -f $0)))/tmp/vimbuildfail"

# File used as a mutex over the Vim source tree
export LOCKFILE="/mnt/ramdisk/vimrc-test/buildlock"

# Vim build artefacts go here
export BUILDDIR="/mnt/ramdisk/vimrc-test/vimbuild"

# Session logs go here
export SESSIONDIR="/mnt/ramdisk/vimrc-test/session"
