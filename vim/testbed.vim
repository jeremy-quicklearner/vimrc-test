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
let s:subjectscript = split(expand('<sfile>:p:h') . '/subject.vim')[-1]

if !exists('g:vimrc_test_expectpath')
    let g:vimrc_test_expectpath = 'expect'
endif

let g:vimrc_test_subject = {'signalcount':-1}
function! s:OnSignal(channel, message)
    let g:vimrc_test_subject.signalcount += 1
endfunction

let s:term_subs = []
" Cursor positions are flaky, so disregard them
call add(s:term_subs, ['^>', '|'])
call add(s:term_subs, ['\([^|]\)>', '\1|'])
" Fully expand every instance of |@{count}, as sometimes Vim partially expands
" them before writing to the file
call add(s:term_subs, ['|\([^@|]\+\)@\(\d\+\)', '\=repeat("|" . submatch(1), submatch(2) + 1)'])

" Remove any of the terminal's responses to t_RV
call add(s:term_subs, ['|^|[|[|>\(|\(\d\|;\)\)\+|c', '\=repeat("| ", len(split(submatch(0), "|")))'])

" Apply text properties to every character, as sometimes Vim shortcuts them in
" different ways
call add(s:term_subs, ['|\(.\)+\([^@|]*\)|\(.\)\([|$]\)', '|\1+\2|\3+\2\4'])

function! s:WaitForSignal(unchangedsignalcount)
    let termnr = g:vimrc_test_subject.termnr
    let row = term_getsize(termnr)[0]
    let waitcount = 0
    while g:vimrc_test_subject.signalcount ==# a:unchangedsignalcount
        " One minute
        if waitcount >=# 1200
            throw 'Signal timeout'
        endif
        let waitcount += 1
        if term_getstatus(termnr) !~# 'running'
            throw 'Subject crashed'
        endif
        let theline = term_getline(termnr, row)
        if theline =~#
       \   '\(Press\|Hit\) ENTER or type command to continue'
            call term_dumpwrite(termnr, g:vimrc_test_subject.dir . '/stall')
            throw 'Subject stalled'
        endif
        if theline =~# 'Not an editor command'
            call term_dumpwrite(termnr, g:vimrc_test_subject.dir . '/stall')
            throw 'Command unknown to subject'
        endif

        call writefile(['LINE ' . theline], g:vimrc_test_subject.dir . '/channel', 'as')
        sleep 50m
    endwhile
endfunction

function! s:IndirectSend(keys)
    if g:vimrc_test_subject.signalcount ==# -1
        throw 'Testbed has not started'
    endif
    let towrite = [a:keys . "\<Ignore>"]
    call writefile(towrite, g:vimrc_test_subject.dir . "/keybuf", "s")
    let unchangedsignalcount = g:vimrc_test_subject.signalcount
    call term_sendkeys(g:vimrc_test_subject.termnr, '$')
    call s:WaitForSignal(unchangedsignalcount)
endfunction

function! VimrcTestBedStart(subjectpath, sessiondir, rows, cols)
    if g:vimrc_test_subject.signalcount !=# -1
        throw 'Testbed already started'
    endif

    set laststatus=2
    set showtabline=2

    " This directory will contain files used for communication between the
    " testbed and subject
    call mkdir(a:sessiondir, 'p')
    silent call system('rm -rf ' . a:sessiondir . '/*')

    " Create a new named pipe - the Signal Pipe
    let signalpipe = a:sessiondir . '/signal'
    silent call system('mkfifo ' . signalpipe)

    " Need three extra rows for the Testbed Vim instance - tabline, statusline,
    " and ex command line
    let &lines=str2nr(a:rows) + 3
    let &columns=str2nr(a:cols)

    " Tail the signal pipe using a channel. The channel will get a message
    " when anything is written to the pipe
    let job = job_start('tail -f ' . signalpipe)
    let channel = job_getchannel(job)
    call ch_setoptions(channel, {'mode':'nl','callback':function('s:OnSignal')})

    " Start the Subject Vim instance in a terminal window. Make it source
    " subject.vim on startup and tell it the name of the signal pipe
    enew!
    let termnr = term_start(
   \    [a:subjectpath, '-w', a:sessiondir . '/keylog', '-S', s:subjectscript],
   \    {'curwin':1}
   \)
    call term_sendkeys(termnr, a:sessiondir . ' ')

    " Toggle off/on the 'number' option to avoid a weird bug in older Vims -
    " some range between 8.0.500ish to 8.2.1500ish
    call term_sendkeys(termnr, ":set nonu\<cr>:set nu\<cr>")

    " Testbed will be ready once the signal arrives
    let g:vimrc_test_subject.termnr = termnr
    let g:vimrc_test_subject.dir = a:sessiondir
    let g:vimrc_test_subject.job = job
    let g:vimrc_test_subject.channel = channel
    let g:vimrc_test_subject.trace = '$$START' . a:rows . ',' . a:cols . '$$'

    " Wait for the subject to write to the signal pipe, indicating it's up and
    " running
    call s:WaitForSignal(-1)

    call term_sendkeys(termnr, ":echo 'fresh subject'\<cr>")
endfunction

function! s:CompareModels(model1, model2)
    let type1 = type(a:model1)
    let type2 = type(a:model2)
    if type1 ==# v:t_dict && type2 ==# v:t_dict
        for k in keys(a:model1)
            if !has_key(a:model2, k)
                return 0
            endif
        endfor
        for [k, v] in items(a:model2)
            " Afterimage buffer numbers are a bit fuzzy - different versions
            " of Vim allocate buffer numbers differently. So only check
            " presence and typing
            if k ==# 'aibuf'
                return has_key(a:model1, k) && type(v) ==# type(a:model1[k])
            endif
            if !has_key(a:model1, k) || !s:CompareModels(a:model1[k], v)
                return 0
            endif
        endfor
        return 1
    elseif type1 ==# v:t_list && type2 ==# v:t_list
        if len(a:model1) !=# len(a:model2)
            return 0
        endif
        for i in range(len(a:model1))
            if !s:CompareModels(a:model1[i], a:model2[i])
                return 0
            endif
        endfor
        return 1
    else
        return a:model1 ==# a:model2
    endif
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

    " VimrcTestSubjectPreCapture forces post-event callbacks to run, and then
    " writes to the signal pipe. The capture needs to involve two separate
    " events inside the subject, so that the subject may return to its event
    " loop after redrawing
    call s:IndirectSend(":call VimrcTestSubjectPreCapture()\n")

    " VimrcTestSubjectCapture is part of subject.vim. It causes the Subject
    " Vim instance to write the message history and Wince model to files in
    " the capture directory. Once done, it writes one character to the signal
    " pipe
    call s:IndirectSend(":call VimrcTestSubjectCapture('" . capname . "')\n")

    call term_wait(g:vimrc_test_subject.termnr, 200)

    " Dump the terminal
    try
        silent call term_dumpwrite(g:vimrc_test_subject.termnr, capdir . '/screen')
    catch /.*/
    endtry

    " If an expected capture exists, compare against it
    let expcapdir = g:vimrc_test_expectpath . '/' . capname
    if isdirectory(expcapdir)
        " Trace
        let act = g:vimrc_test_subject.trace
        let exp = readfile(expcapdir . '/trace')[0]
        if act !=# exp
            throw 'Hash collision at ' . capname
        endif

        " Message history
        try
            let act = readfile(capdir . '/messages')
        catch /E484/
            throw 'Messages Missing'
        endtry
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

        " Wince Model
        let act = json_decode(readfile(capdir . '/wince')[0])
        let exp = json_decode(readfile(expcapdir . '/wince')[0])
        if !s:CompareModels(act, exp)
            throw 'Wince model at ' . capname . ' does not match expected'
        endif

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

    call s:IndirectSend(a:keys)
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
    let waitcount = 0
    while index(split(term_getstatus(g:vimrc_test_subject.termnr), ','), 'finished') ==# -1
        call term_wait(g:vimrc_test_subject.termnr, 100)
        " Five seconds
        if waitcount >=# 100
            break
        endif
        let waitcount += 1
    endwhile
    call ch_close(g:vimrc_test_subject.channel)
    call job_stop(g:vimrc_test_subject.job)
    call delete(g:vimrc_test_subject.dir . '/signal')
    let g:vimrc_test_subject = {'signalcount':-1}
endfunction

function! VimrcTestBedExecuteTrace(subjectpath, sessiondir, trace, finish)
    let remainingtrace = a:trace
    let starttime = localtime()
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
            if filereadable(a:sessiondir . '/err')
                return '[FAIL] ' . a:label . ': ' . readfile(a:sessiondir . '/err')[-1]
            endif
        endwhile
    catch /.*/
        call writefile([v:throwpoint, v:exception], a:sessiondir . '/err', 's')
    finally
        if a:finish && g:vimrc_test_subject.signalcount !=# -1
            call writefile([sha256(g:vimrc_test_subject.trace)], a:sessiondir . '/last', 's')
            call writefile([localtime() - starttime], a:sessiondir . '/time', 's')
            call VimrcTestBedStop()
        endif
    endtry
endfunction
