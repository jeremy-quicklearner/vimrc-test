#!/bin/bash

source $(dirname $(readlink -f $0))/sh/config.sh

$(dirname $(readlink -f $0))/py/runlocal.py
