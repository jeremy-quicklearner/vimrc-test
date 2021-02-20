source <sfile>:p:h/testbed.vim
source <sfile>:p:h/label.vim

" Keys typed so far, not yet recorded
let s:sofar = ''

function! s:Start(rows, cols)
    if a:rows + 3 ># &lines
        throw 'Need a taller terminal to accomodate ' . a:rows . ' rows'
    endif

    if a:cols ># &columns
        throw 'Need a wider terminal to accomodate ' . a:cols . ' columns'
    endif

    call VimrcTestBedStart(v:progpath, 'record-' . string(getpid()), a:rows, a:cols)
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
   \    '3. Stop recording',
   \    '4. Resize terminal'
   \])
    if choice ==# 1
        let s:sofar .= '$'
        call term_sendkeys(g:vimrc_test_subject.termnr, '$')
    elseif choice ==# 2
        call s:RecordKeys()
        call VimrcTestBedCapture()
    elseif choice ==# 3
        call s:RecordKeys()
        let finaltrace = g:vimrc_test_subject.trace
        let finalhash = sha256(finaltrace)
        let dir = g:vimrc_test_subject.dir
        call VimrcTestBedStop()
        let label = '$NO$LABEL$'
        while label ==# '$NO$LABEL$'
            let label = input("\nLabel? (leave blank to abandon recording) ")
            if empty(label)
                break
            endif
            if has_key(g:vimrc_test_label, label)
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
        call mkdir('expect', 'p')
        echo system('cp -rv ' . dir . '/* expect/')
        call system('rm -r ' . dir)
        call writefile([
       \    'let g:vimrc_test_label.' .
       \    label .
       \    ' = "' .
       \    finalhash .
       \    '"'
       \], 'label.vim', 'a')
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
        sleep 100m
        call term_wait(g:vimrc_test_subject.termnr)
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

function! VimrcTestRecord()
    call s:Start(&lines - 3, &columns)
    while 1
        call VimrcTestRecordLoop()
    endwhile
endfunction

call VimrcTestRecord()
