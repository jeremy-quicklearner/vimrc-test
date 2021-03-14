" Script to run inside the Subject Vim instance (See: testbed.vim)

" Vim 7.4.1304+
if exists('json_encode')
    let s:Json = function('json_encode')

" Vim 7.4.1154 - 7.4.1303
elseif exists('jsonencode')
    let s:Json = function('jsonencode')

" Older
else
    let s:t = jer_util#Types()
    function! s:Json(expr)
        let texpr = type(a:expr)
        if texpr ==# s:t.number
            return string(a:expr)
        elseif texpr ==# s:t.string
            return '"' . a:expr . '"'
        elseif texpr ==# s:t.list
            let strs = []
            for val in a:expr
                call add(strs, s:Json(val))
            endfor
            return '[' . join(strs, ',') . ']'
        elseif texpr ==# s:t.dict
            let strs = []
            for [k, v] in items(a:expr)
                call add(strs, '"' . k . '":' . s:Json(v))
                unlet v
            endfor
            return '{' . join(strs, ',') . '}'
        else
            throw 'Failed to serialize ' . string(a:expr)
        endif
    endfunction
endif

function! VimrcTestSubjectCapture(capname)
    " Use the directory created by the testbed
    let capdir = s:dir . '/' . a:capname

    " Force-run post-event callbacks here to avoid race conditions with the
    " testbed. Also redraw
    call jer_pec#Run()
    redraw

    let wincemodel = []
    for tabnr in range(1, tabpagenr('$'))
        call add(wincemodel, {
       \    'uberwin': gettabvar(tabnr, 'wince_uberwin', 0),
       \    'supwin': gettabvar(tabnr, 'wince_supwin', 0),
       \    'subwin': gettabvar(tabnr, 'wince_subwin', 0)
       \})
    endfor

    " Can't use execute() in Vim <=8.0
    let messgs = ''
    redir => messgs
        messages
    redir END
    call writefile(split(messgs, "\n"),  capdir . '/messages', 's')
    call writefile([s:Json(wincemodel)], capdir . '/wince',    's')

    " Write 'captured subject' to the bottom line, to avoid flaky presence of
    " 'call VimrcTestSubjectCapture('...') text
    echo 'captured subject'

    " Write one character to the signal file, unblocking the testbed so it can
    " dump the terminal in which the subject is running
    " Append Mode for writefile() isn't supported in older versions of Vim,
    " so use a shell
    silent call system('echo v >> ' . s:dir . '/signal')
endfunction

" Use conceallevel 3 in Undotree windows to hide timestamps
autocmd FileType undotree set conceallevel=3

" Use the jeremy-test colour scheme
colorscheme jeremy-test

" Get the signal file name from the user
let s:dir = ''
let nextch = nr2char(getchar())
while nextch != ' '
    let s:dir .= nextch
    let nextch = nr2char(getchar())
endwhile

" Don't show [Vim X.X] in the tabline
let g:override_vim_version_string = 1

" Empty all the registers
for regname in [
\   'a', 'b', 'c', 'd', 'e',
\   'f', 'g', 'h', 'i', 'j',
\   'k', 'l', 'm', 'n', 'o',
\   'p', 'q', 'r', 's', 't',
\   'u', 'v', 'x', 'w', 'y',
\   'z', '0', '1', '2', '3',
\   '4', '5', '6', '7', '8',
\   '9', '"', '-', '/'
\]
    call setreg(regname, '')
endfor

" Force-run post-event callbacks here to avoid race conditions with the
" testbed. Also redraw
call jer_pec#Run()
redraw

call writefile(['v'], s:dir . '/signal', 'as')