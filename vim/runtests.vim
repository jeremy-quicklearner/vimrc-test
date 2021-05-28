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
for [label, tracehash] in items(g:vimrc_test_label_tp)
    let trace = readfile(g:vimrc_test_expectpath . '/' . tracehash . '/trace')[0]
    " This function comes from testbed.vim
    call VimrcTestBedExecuteTrace(
   \    g:vimrc_test_subjectpath,
   \    g:vimrc_test_sessionname . '/' . label,
   \    trace,
   \    1
   \)
endfor

function! s:ResultByLabel(label, exphash)
    let dir = g:vimrc_test_sessionname . '/' . a:label
    let haserr = filereadable(dir . '/err')
    let haslast = filereadable(dir . '/last')

    if haslast
        let acthash = readfile(dir . '/last')[0]
        let ls = globpath(dir, '*', 0, 1)
        let re = '(' . join([acthash, 'last', 'stall', 'err'], ')|(') . ')'
        call filter(ls, 're !~# fnamemodify(v:val, ":t")')
        call filter(ls, 'delete(v:val, "rf")')
    endif

    if haserr
        return '[FAIL] ' . a:label . ': ' . readfile(dir . '/err')[-1]
    endif

    if !haslast
        return '[!!!!] ' . a:label . ': Bad session'
    endif

    if a:exphash !=# acthash
        return '[!!!!] ' . a:label . ': Traces don''t match, but no error log'
    endif
    return '[pass] ' . a:label
endfunction

let s:report_bufnr = bufnr(g:vimrc_test_sessionname . '/report', 1)
silent execute 'sbuffer ' . g:vimrc_test_sessionname . '/report'
call setbufvar(s:report_bufnr, '&swapfile', 0)
for [label, exphash] in items(g:vimrc_test_label_tp)
    call setbufline(
   \    s:report_bufnr,
   \    line('$') + 1,
   \    [s:ResultByLabel(label, exphash)]
   \)
endfor
call setbufline(s:report_bufnr, 1, 'vimrc Test Report: ' . g:vimrc_test_sessionname)
write

qall!
