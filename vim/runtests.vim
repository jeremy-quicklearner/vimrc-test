source <sfile>:p:h/testbed.vim
source <sfile>:p:h/label.vim

if !exists('g:vimrc_test_subjectpath')
    let g:vimrc_test_subjectpath = v:progname
endif
if !exists('g:vimrc_test_expectpath')
    let g:vimrc_test_expectpath = 'expect'
endif
if !exists('g:vimrc_test_sessionname')
    let g:vimrc_test_sessionname = 'testrun'
endif

call mkdir(g:vimrc_test_sessionname, 'p')
call system('rm -rf ' . g:vimrc_test_sessionname . '/*')

" vimrc_test_label_tp comes from label.vim
try
    for [label, testpoint] in items(g:vimrc_test_label_tp)
        if has_key(testpoint, 'has')
            let found = 0
            for requirement in testpoint.has
                if system(
               \    g:vimrc_test_subjectpath .
               \    ' -e -s -c "if has(''' . 
               \    requirement .
               \    ''') | cquit | else | exit | endif" > /dev/null 2>&1 ; echo -n $?'
               \) ==# 0
                    let found = 1
                    break
                endif
            endfor
            if found
                call mkdir(g:vimrc_test_sessionname . '/' . label, 'p')
                call writefile([requirement], g:vimrc_test_sessionname . '/' . label . '/req', 's')
                continue
            endif
        endif
    
        if has_key(testpoint, 'exists')
            let found = 0
            for requirement in testpoint.exists
                if system(
               \    g:vimrc_test_subjectpath .
               \    ' -e -s -c "if has(''' . 
               \    requirement .
               \    ''') | cquit | else | exit | endif" > /dev/null 2>&1 ; echo -n $?'
               \) ==# 0
                    let found = 1
                    break
                endif
            endfor
            if found
                call mkdir(g:vimrc_test_sessionname . '/' . label, 'p')
                call writefile([requirement], g:vimrc_test_sessionname . '/' . label . '/req', 's')
                continue
            endif
        endif
    
        let trace = readfile(g:vimrc_test_expectpath . '/' . testpoint.tracehash . '/trace')[0]
    
        for i in range(10)
            " This function comes from testbed.vim
            call VimrcTestBedExecuteTrace(
           \    g:vimrc_test_subjectpath,
           \    g:vimrc_test_sessionname . '/' . label,
           \    trace,
           \    1
           \)
            if !filereadable(g:vimrc_test_sessionname . '/' . label . '/err') ||
           \   index([
           \       'Signal timeout',
           \       'Subject stalled',
           \       'Messages Missing'
           \   ], readfile(g:vimrc_test_sessionname . '/' . label . '/err')[-1]) ==# -1
                call writefile([i], g:vimrc_test_sessionname . '/' . label . '/retry', 's')
                break
            endif
        endfor
    endfor
catch /.*/
    call writefile([v:throwpoint, v:exception], g:vimrc_test_sessionname . '/err', 's')
endtry

function! s:ResultByLabel(label, exphash)
    let dir = g:vimrc_test_sessionname . '/' . a:label
    if filereadable(dir . '/req')
        return '[skip] ' . a:label . ': subject is missing requirement ' . readfile(dir . '/req')[-1]
    endif

    let haserr = filereadable(dir . '/err')
    let haslast = filereadable(dir . '/last')

    if haslast
        let acthash = readfile(dir . '/last')[0]
        let ls = globpath(dir, '*', 0, 1)
        let re = '(' . join([acthash, 'last', 'time', 'retry', 'keylog', 'keybuf', 'stall', 'err'], ')|(') . ')'
        call filter(ls, 're !~# fnamemodify(v:val, ":t")')
        call filter(ls, 'delete(v:val, "rf")')
    endif

    if haserr
        return '[FAIL] ' . a:label . ': ' . readfile(dir . '/err')[-1]
    endif

    if !haslast
        if filereadable(g:vimrc_test_sessionname . '/err')
            return '[!!!!] ' . a:label . ': Bad session: ' .  readfile(g:vimrc_test_sessionname . '/err')[-1]
        endif
        return '[!!!!] ' . a:label . ': Bad session'
    endif

    if a:exphash !=# acthash
        return '[!!!!] ' . a:label . ': Traces don''t match, but no error log'
    endif
    return '[pass][' . readfile(dir . '/retry')[0] . 'r][' . readfile(dir . '/time')[0] . 's] '. a:label
endfunction

let s:report_bufnr = bufnr(g:vimrc_test_sessionname . '/report', 1)
silent execute 'sbuffer ' . g:vimrc_test_sessionname . '/report'
call setbufvar(s:report_bufnr, '&swapfile', 0)
for [label, testpoint] in items(g:vimrc_test_label_tp)
    call setbufline(
   \    s:report_bufnr,
   \    line('$') + 1,
   \    [s:ResultByLabel(label, testpoint.tracehash)]
   \)
endfor
call setbufline(s:report_bufnr, 1, 'vimrc Test Report: ' . g:vimrc_test_sessionname)
write

qall!
