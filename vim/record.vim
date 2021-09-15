source <sfile>:p:h/testbed.vim
source <sfile>:p:h/label.vim

let s:labelpath = split(expand('<sfile>:p:h') . '/label.vim')[-1]

" Keys typed so far, not yet recorded
let s:sofar = ''

" Tracehash of most recent capture
let s:lastcap = ''

function! s:Start(startfrom, rows, cols)
    if empty(a:startfrom)
        if a:rows + 3 ># &lines
            throw 'Need a taller terminal to accomodate ' . a:rows . ' rows'
        endif

        if a:cols ># &columns
            throw 'Need a wider terminal to accomodate ' . a:cols . ' columns'
        endif

        call VimrcTestBedStart(v:progpath, g:vimrc_test_sessionname, a:rows, a:cols)
    else
        if has_key(g:vimrc_test_label, a:startfrom)
            let sfdict = g:vimrc_test_label[a:startfrom]
        elseif has_key(g:vimrc_test_label_tp, a:startfrom)
            let sfdict = g:vimrc_test_label_tp[a:startfrom]
        else
            throw 'Cannot start recording from nonexistent label ' . a:startfrom
        endif
        let tracehash = sfdict.tracehash

        let s:reqhas = get(sfdict, 'has', 0)
        let s:reqexists = get(sfdict, 'exists', 0)

        let trace = readfile(g:vimrc_test_expectpath . '/' . tracehash . '/trace')[0]
        call VimrcTestBedExecuteTrace(v:progpath, g:vimrc_test_sessionname, trace, 0)
    endif
endfunction

function! s:RecordKeys()
    if empty(s:sofar)
        return
    endif
    let g:vimrc_test_subject.trace .= '$$KEYS' . s:sofar . '$$'
    let s:sofar = ''
endfunction

function! s:Resize(rows, cols)
    if a:rows + 3 ># &lines
        throw 'Need a taller terminal to accomodate ' . a:rows . ' rows'
    endif

    if a:cols ># &columns
        throw 'Need a wider terminal to accomodate ' . a:cols . ' columns'
    endif

    call VimrcTestBedResize(a:rows, a:cols)
endfunction

function! s:Escape()
    let choice = inputlist([
   \    'Select an option:',
   \    '1. Pass ''$'' keystroke to subject',
   \    '2. Capture',
   \    '3. Stop Recording',
   \    '4. Resize terminal'
   \])
    if choice ==# 1
        let s:sofar .= '$'
        call term_sendkeys(g:vimrc_test_subject.termnr, '$')
    elseif choice ==# 2
        call s:RecordKeys()
        call VimrcTestBedCapture()
        let s:lastcap = g:vimrc_test_subject.trace
    elseif choice ==# 3
        call s:RecordKeys()
        let finalhash = sha256(s:lastcap)
        let dir = g:vimrc_test_subject.dir
        call VimrcTestBedStop()
        let label = '$NO$LABEL$'
        while label ==# '$NO$LABEL$'
            let label = input("\nLabel? (leave blank to abandon recording) ")
            if empty(label)
                break
            endif
            if has_key(g:vimrc_test_label, label) ||
           \   has_key(g:vimrc_test_label_tp, label)
                echo 'Label ' . label . ' is already in use'
                let label = '$NO$LABEL$'
            endif
            try
                let adict = {}
                execute 'let adict.' . label . ' = 0'
            catch /.*/
                echo 'Label "' . label . '" is not valid as a dict key'
                let label = '$NO$LABEL$'
            endtry
        endwhile
        if empty(label)
            exit
        endif
        call delete(dir . '/last')
        call delete(dir . '/keylog')
        call mkdir(g:vimrc_test_expectpath, 'p')
        call system('cp -rv ' . dir . '/* ' . g:vimrc_test_expectpath .. '/')
        call system('rm -r ' . dir)
        let choice = inputlist([
       \    "\nUse label " . label . " as testpoint?",
       \    '1. Yes',
       \    '2. No'
       \])
        if choice ==# 1
            let labeldict = 'g:vimrc_test_label_tp'
        " Default to No
        else
            let labeldict = 'g:vimrc_test_label'
        endif

        let labelline = 'let ' . labeldict . '.' . label .' = {"tracehash":"' .
       \    finalhash . '"'

        if type(s:reqhas) ==# v:t_list
            let labelline .= ',"has":' . string(s:reqhas)
        endif

        if type(s:reqexists) ==# v:t_list
            let labelline .= ',"exists":' . string(s:reqexists)
        endif

        let labelline .= '}'

        call writefile([labelline], s:labelpath, 'a')
        exit
    elseif choice ==# 4
        let rows = input("\nRows? (current: " . string(&lines - 3) . ') ')
        let cols = input("\nColumns? (current: " . string(&columns) . ') ')
        call s:RecordKeys()
        call s:Resize(rows, cols)
    endif
endfunction

function! VimrcTestRecordLoop()
    let chr = 0
    while !chr
        eall term_wait(g:vimrc_test_subject.termnr)
        redraw
        let chr = getchar(0)
    endwhile
    if type(chr) ==# v:t_number
        let chr = nr2char(chr)
    endif
    if chr ==# '$'
        call s:Escape()
        return
    endif

    let s:sofar .= chr
    call term_sendkeys(g:vimrc_test_subject.termnr, chr)
endfunction

function! VimrcTestRecord(startfrom)
    call s:Start(a:startfrom, &lines - 3, &columns)
    while 1
        call VimrcTestRecordLoop()
    endwhile
endfunction
