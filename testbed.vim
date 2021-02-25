" The test environment contains *two* Vim instances - the Testbed and the
" Subject.
" The Subject is the one that undergoes the use case being tested.
" The Testbed manages the subject inside a terminal window
" Between runs of keystrokes sent to the Subject, a 'Capture' process can be
" performed to record information about the state of the Subject and write it
" to the filesystem where it can be compared against a different, 'expected'
" snapshot. The following state is recorded:
" 1. The terminal screen contents (via term_dumpwrite)
" 2. The message history (as per :messages)
" 3. The Tab-specific Wince model for all tabs

" The testbed consumes a 'trace' - a string of keys with escape sequences
" that indicate when to perform a capture, when to resize the terminal, etc

let g:vimrc_test_subject = {'signalcount':-1}
function! s:OnSignal(channel, message)
    let g:vimrc_test_subject.signalcount += 1
endfunction

let s:term_subs = [
" Cursor positions are flaky, so disregard them
\    [
\        '^>',
\        '|'
\    ], [
\        '\(|\)\@!>',
\        '|'
" Fully expand every instance of |@{count}, as sometimes Vim partially expands
" them before writing to the file
\    ], [
\        '|\([^@|]\+\)@\(\d\+\)',
\        '\=repeat("|" . submatch(1), submatch(2))'
\    ], [
\        '|\(.\)+\([^@|]*\)|\(.\)\([|$]\)',
\        '|\1+\2|\3+\2\4'
\    ]
\]

function! VimrcTestBedStart(subjectpath, sessiondir, rows, cols)
    if g:vimrc_test_subject.signalcount !=# -1
        throw 'Testbed already started'
    endif

    " Need three extra rows for the Testbed Vim instance - tabline, statusline,
    " and ex command line
    let &lines=str2nr(a:rows) + 3
    let &columns=str2nr(a:cols)

    " This directory will contain files used for communication between the
    " testbed and subject
    call delete(a:sessiondir, 'rf')
    call mkdir(a:sessiondir, 'p')

    " Create a new file - the Signal File
    let signalfile = a:sessiondir . '/signal'
    call writefile([], signalfile, 's')

    " Tail the signal file using a channel. The channel will get a message
    " when anything is written to the file
    let job = job_start('tail -f ' . signalfile)
    let channel = job_getchannel(job)
    call ch_setoptions(channel, {'mode':'nl','callback':function('s:OnSignal')})

    " Start the Subject Vim instance in a terminal window. Make it source
    " subject.vim on startup and tell it the name of the signal file
    let termnr = term_start([a:subjectpath, '-S', 'subject.vim'], {'curwin':1})
    call term_sendkeys(termnr, a:sessiondir . ' ')

    " Wait for the subject to write to the signal file, indicating it's up and
    " running
    while g:vimrc_test_subject.signalcount ==# -1
        sleep 50m
    endwhile

    " Toggle off/on the 'number' option to avoid that weird bug in older Vims
    call term_sendkeys(termnr, ":set nonu\<cr>:set nu\<cr>:echo 'fresh subject'\<cr>")

    " Testbed is ready
    let g:vimrc_test_subject = {
   \    'termnr': termnr,
   \    'dir': a:sessiondir,
   \    'job': job,
   \    'channel': channel,
   \    'signalcount': 0,
   \    'trace': '$$START' . a:rows . ',' . a:cols . '$$'
   \}
endfunction

" Perform a capture
function! VimrcTestBedCapture()
    if g:vimrc_test_subject.signalcount ==# -1
        throw 'Testbed has not started'
    endif

    " Note the Capture in the trace, then hash the trace to get the capture
    " directory name
    let g:vimrc_test_subject.trace .= '$$CAP$$'
    let capname = sha256(g:vimrc_test_subject.trace)

    " First, prepare a directory
    let capdir = g:vimrc_test_subject.dir . '/' . capname 
    call mkdir(capdir, 'p')

    " Write the trace
    call writefile([g:vimrc_test_subject.trace], capdir . '/trace', 's')

    " VimrcTestSubjectCapture is part of subject.vim. It causes the Subject
    " Vim instance to write the Jersuite log buffer, message history, and
    " Wince model to files in the capture directory. Once done, it writes one
    " character to the signal file
    let unchangedsignalcount = g:vimrc_test_subject.signalcount
    call term_sendkeys(
   \    g:vimrc_test_subject.termnr,
   \    ":call VimrcTestSubjectCapture('" . capname . "')\n"
   \)

    " Wait for that character to appear in the channel from tailing the signal
    " file, and for any terminal updates. This avoids dumping the terminal
    " before the Subject is ready
    while g:vimrc_test_subject.signalcount ==# unchangedsignalcount
        sleep 50m
    endwhile

    call term_wait(g:vimrc_test_subject.termnr)

    " Dump the terminal
    try
        silent call term_dumpwrite(g:vimrc_test_subject.termnr, capdir . '/screen')
    catch /.*/
    endtry

    " If an expected capture exists, compare against it
    let expcapdir = 'expect/' . capname
    if isdirectory(expcapdir)
        " Trace
        let act = g:vimrc_test_subject.trace
        let exp = readfile(expcapdir . '/trace')[0]
        if act !=# exp
            throw 'Hash collision at ' . capname
        endif

        " Message history
        let act = readfile(capdir . '/messages')
        let exp = readfile(expcapdir . '/messages')
        let actlen = len(act)
        let explen = len(exp)
        if actlen != explen
            throw 'Message history at ' . capname . ' does not match expected'
        endif
        for idx in range(actlen)
            if act[idx] !=# exp[idx]
                throw 'Message history at ' . capname . ' does not match expected'
            endif
        endfor

        " Terminal
        let act = readfile(capdir . '/screen')
        let exp = readfile(expcapdir . '/screen')
        let actlen = len(act)
        let explen = len(exp)
        if actlen != explen
            throw 'Terminal contents at ' . capname . ' do not match expected'
        endif
        for idx in range(actlen)
            if act[idx] ==# exp[idx]
                continue
            endif
            for [pat, sub] in s:term_subs
                let prev = ''
                while prev !=# act[idx]
                    let prev = act[idx]
                    let act[idx] = substitute(act[idx], pat, sub, 'g')
                endwhile
                let prev = ''
                while prev !=# exp[idx]
                    let prev = exp[idx]
                    let exp[idx] = substitute(exp[idx], pat, sub, 'g')
                endwhile
            endfor
            if act[idx] !=# exp[idx]
                throw 'Terminal contents at ' . capname . ' do not match expected'
            endif
        endfor

        " Wince Model
        let act = json_decode(readfile(capdir . '/wince')[0])
        let exp = json_decode(readfile(expcapdir . '/wince')[0])
        if act !=# exp
            throw 'Wince model at ' . capname . ' does not match expected'
        endif
    endif

    redraw
endfunction

" Send keystrokes to the Subject
function! s:Feedkeys(keys)
    if g:vimrc_test_subject.signalcount ==# -1
        throw 'Testbed has not started'
    endif

    if a:keys =~# '\$\$'
        throw 'Cannot pass \$\$ as it would mess up testbed implementation'
    endif

    call term_sendkeys(g:vimrc_test_subject.termnr, a:keys)
    let g:vimrc_test_subject.trace .= '$$KEYS' . a:keys . '$$'
endfunction

function! VimrcTestBedResize(rows, cols)
    if g:vimrc_test_subject.signalcount ==# -1
        throw 'Testbed has not started'
    endif

    if a:rows >=# 0
        " Need three extra rows for the Testbed Vim instance - tabline, statusline,
        " and ex command line
        let &lines = a:rows + 3
    endif
    if a:cols >=# 0
        let &columns = a:cols
    endif

    redraw
    let g:vimrc_test_subject.trace .= '$$SIZE' . a:rows . ',' . a:cols . '$$'
endfunction

" Stop the Subject and Testbed
function! VimrcTestBedStop()
    if g:vimrc_test_subject.signalcount ==# -1
        throw 'Testbed has not started'
    endif
    call term_sendkeys(g:vimrc_test_subject.termnr, "\<esc>:qa!\n")
    while index(split(term_getstatus(g:vimrc_test_subject.termnr), ','), 'finished') ==# -1
        call term_wait(g:vimrc_test_subject.termnr, 100)
    endwhile
    call ch_close(g:vimrc_test_subject.channel)
    call job_stop(g:vimrc_test_subject.job)
    call delete(g:vimrc_test_subject.dir . '/signal')
    let g:vimrc_test_subject = {'signalcount':-1}
endfunction

function! VimrcTestBedExecuteTrace(subjectpath, sessiondir, trace)
    let remainingtrace = a:trace
    try
        while !empty(remainingtrace)
            " Consume item
            if remainingtrace !~# '^\$\$'
                throw 'Bad trace'
            endif
            let [item, itemstartidx, itemendidx] = matchstrpos(
           \    remainingtrace,
           \    '^\$\$.\{-}\$\$'
           \)
            let remainingtrace = remainingtrace[itemendidx:]
            let item = item[2:-3]

            if item =~# '^CAP'
                call VimrcTestBedCapture()
            elseif item =~# '^KEYS'
                let keys = item[4:]
                call s:Feedkeys(keys)
            elseif item =~# '^START'
                let [rows, cols] = split(item[5:], ',')
                call VimrcTestBedStart(a:subjectpath, a:sessiondir, rows, cols)
            elseif item =~# '^SIZE'
                let [rows, cols] = split(item[4:], ',')
                call VimrcTestBedResize(rows, cols)
            else
                throw 'Bad trace item: ' . item
            endif
        endwhile
    catch /.*/
        call writefile([v:throwpoint, v:exception], a:sessiondir . '/err', 's')
    finally
        call writefile([sha256(g:vimrc_test_subject.trace)], a:sessiondir . '/last', 's')
        call VimrcTestBedStop()
    endtry
endfunction
