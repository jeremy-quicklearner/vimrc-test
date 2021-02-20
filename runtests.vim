source testbed.vim
source label.vim

if !exists('g:subjectpath')
    let g:vimrc_test_subjectpath = v:progname
endif
if !exists('g:sessionname')
    let g:vimrc_test_sessionname = 'testrun'
endif

call delete(g:vimrc_test_sessionname, 'rf')

" vimrc_test_label comes from label.vim
for [label, tracehash] in items(g:vimrc_test_label)
    let trace = readfile('expect/' . tracehash . '/trace')[0]
    " This function comes from testbed.vim
    call VimrcTestBedExecuteTrace(
   \    g:vimrc_test_subjectpath,
   \    g:vimrc_test_sessionname . '/' . label,
   \    trace
   \)
endfor

function! s:ResultByLabel(label, exphash)
    if !filereadable(g:vimrc_test_sessionname . '/' . a:label . '/last')
        return '[!!!!] ' . a:label . ': Bad session'
    endif
    let acthash = readfile(g:vimrc_test_sessionname . '/' . a:label . '/last')[0]
    if a:exphash !=# acthash
        if !filereadable(g:vimrc_test_sessionname . '/' . a:label . '/err')
            return '[!!!!] ' . a:label . ': Traces don''t match, but no error log'
        else
            return '[FAIL] ' . a:label . ': ' . readfile(
           \    g:vimrc_test_sessionname . '/' . a:label . '/err'
           \)[-1]
        endif
    endif
    return '[PASS] ' . a:label
endfunction

let s:report_bufnr = bufnr(g:vimrc_test_sessionname . '/report', 1)
silent execute 'buffer ' . g:vimrc_test_sessionname . '/report'
call setbufvar(s:report_bufnr, '&swapfile', 0)
for [label, exphash] in items(g:vimrc_test_label)
    call setbufline(
   \    s:report_bufnr,
   \    line('$') + 1,
   \    [s:ResultByLabel(label, exphash)]
   \)
endfor
call setbufline(s:report_bufnr, 1, 'vimrc Test Report: ' . g:vimrc_test_sessionname)
write

exit
