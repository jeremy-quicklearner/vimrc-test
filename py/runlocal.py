#!/usr/bin/python3

import re
import os
import sys
import time
import unicodedata
import subprocess
from multiprocessing.dummy import Pool

cmd = 'git ls-remote --tags https://github.com/vim/vim'
versions = subprocess.run(cmd, capture_output=True, text=True, shell=True).stdout
versions = [re.sub(r'^.*refs/tags/v', '', v) for v in versions.split('\n')][:-1]

# Only Consider 7.3+
versions = [v for v in versions if not re.match(r'^7\.[0-2]', v)]
if '8.2.2366' not in versions:
    raise Exception('Failed to fetch tags from Github')

# 7.4a, 7.4b, etc.
weirdversions = []
nonweirdversions = []
for v in versions:
    if re.match(r'^\d+\.\d+(\.\d+)?$', v):
        nonweirdversions += [v]
    else:
        weirdversions += [v]

nonweirdversions.sort(key=lambda v: list(map(int, v.split('.'))))

# Reinsert weird versions before 7.4
idx = nonweirdversions.index('7.4')
versions = nonweirdversions[:idx] + weirdversions + nonweirdversions[idx:]
versions = ['v' + v for v in versions]

# Exclude unsupported versions with breaking bugs
exclude = set([])

# Require at least 7.3.1115 - first version in which number and relativenumber
# options play well together
for p in range(1115):
    exclude.add('v7.3.%s' % '{:03d}'.format(p))
exclude.add('v7.3')

# cursorline only drawn in current window
for p in range(1277, 1282):
    exclude.add('v7.3.%s' % p)

# ':options' command is broken
for p in range(201, 230):
    exclude.add('v7.4.%s' % p)

# Weird effects of missing type cast
for p in range(794, 796):
    exclude.add('v7.4.%s')

# Issues with typing
for p in range(1155, 1163):
    exclude.add('v7.4.%s' % '{:04d}'.format(p))

# Issues with funcrefs
for p in range(1577, 1581):
    exclude.add('v7.4.%s' % '{:04d}'.format(p))

# Bug in options window
exclude.add('v7.4.1808')

# Something goes wrong with the has() checks
for p in range(2073, 2078):
    exclude.add('v7.4.%s' % '{:04d}'.format(p))

# Issues calling autoloaded funcrefs
for p in range(2137, 2142):
    exclude.add('v7.4.%s' % '{:04d}'.format(p))

# Crashes on start
exclude.add('v8.0.0693')

# Colours are different
for p in range(791, 829):
    exclude.add('v8.0.%s' % '{:04d}'.format(p))

# writefile() with Fsync fails when writing to a pipe
for p in range(1305, 1335):
    exclude.add('v8.0.%s' % '{:04d}'.format(p))

# Some sort of memory-related bug
exclude.add('v8.1.0580')

# QuickFixLine highlight group is broken
for p in range(2029, 2040):
    exclude.add('v8.1.%s' % '{:04d}'.format(p))

# Opening quickfix window is broken
for p in range(1547, 1549):
    exclude.add('v8.1.%s' % '{:04d}'.format(p))

# Issues with redrawing that cause a race condition between subject and testbed
for p in range(1587, 1909):
    exclude.add('v8.1.%s' % p)

# Python integration is broken, which breaks vim-plug
exclude.add('v8.2.0149')

# No / at the start of absolute file paths in tabline
for p in range(208, 215):
    exclude.add('v8.2.%s' % '{:04d}'.format(p))

# Top tilde under buffer text is missing in these versions
for p in range(936, 1165):
    exclude.add('v8.2.%s' % '{:04d}'.format(p))

# ':options' command is broken
for p in range(1639, 1642):
    exclude.add('v8.2.%s' % '{:04d}'.format(p))

# Vimscript bugs
exclude.add('v8.2.2250')
exclude.add('v8.2.2670')

# Course select
course = os.environ['COURSE']
if course == 'ALL':
    pass
elif course == 'ALL000':
    versions = [v for v in versions if re.match(r'^.*000$', v)]
elif course == 'ALL00':
    versions = [v for v in versions if re.match(r'^.*00$', v)]
elif course == 'ALL0':
    versions = [v for v in versions if re.match(r'^.*0$', v)]
elif course.startswith('MINMAX'):
    nversions = []
    min = os.environ['COURSE_MIN']
    max = os.environ['COURSE_MAX']
    inrange = False
    for v in versions:
        if not inrange and v == min:
            inrange = True

        if inrange:
            nversions += [v]

        if inrange and v == max:
            break

    if course == 'MINMAX':
        pass
    elif course == 'MINMAX0':
        nversions = [v for v in nversions if re.match(r'^.*0$', v)]
    elif course == 'MINMAX00':
        nversions = [v for v in nversions if re.match(r'^.*00$', v)]
    else:
        raise Exception('Unknown course %s' % course)
    versions = nversions
else:
    raise Exception('Unknown course %s' % course)

runsh = os.environ['RUNSH']
vimrcdir = os.environ['VIMRCDIR']
cmdfmt = '%s %%s %s' % (runsh, vimrcdir)

def runversion(v):
    if v in exclude:
        return '[%s][skip][Unsupported]\n' % v
    cmd = cmdfmt % v
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        shell=True
    ).stdout

print('%d versions in course %s' % (len(versions), course))
starttime = time.time()
p = Pool(int(os.environ['NUM_THREADS']))
for output in p.imap(runversion, versions):
    print(output, end='', flush=True)

elapsed = time.time() - starttime
print('Finished in %dw %dd %dh %dm %ds' % (elapsed / 604800,
                                          (elapsed % 604800) / 86400,
                                          (elapsed % 86400) / 3600,
                                          (elapsed % 3600) / 60,
                                          elapsed % 60))
