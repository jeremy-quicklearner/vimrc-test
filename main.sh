#!/bin/bash

source $(dirname $(readlink -f $0))/sh/config.sh

export RUNSH=$(dirname $(readlink -f $0))/sh/run.sh

$(dirname $(readlink -f $0))/py/runlocal.py
