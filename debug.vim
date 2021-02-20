if !exists('*win_getid')
    echoerr 'debug.vim requires native winids'
endif

let s:jsonindent = '  '
function! s:DictKeyCmp(key1, key2)
    let len1 = len(a:key1)
    let len2 = len(a:key2)
    if len(a:key1) !=# len(a:key2)
        return len1 <# len2
    endif
    if a:key1 <# a:key2
        return -1
    endif

    " Assume dict keys can't be duplicates
    return 1
endfunction
    
function! s:PrettyJson(expr)
    let texpr = type(a:expr)
    if texpr ==# v:t_number
        return [string(a:expr)]
    elseif texpr ==# v:t_string
        return ['"' . a:expr . '"']
    elseif texpr ==# v:t_list
        if empty(a:expr)
            return ['[]']
        endif
        let res = ['[']
        for item in a:expr
            for jsonline in s:PrettyJson(item)
                call add(res, s:jsonindent . jsonline)
            endfor
            let res[-1] .= ','
        endfor
        let res[-1] = res[-1][:-2]
        call add(res, ']')
        return res
    elseif texpr ==# v:t_dict
        if empty(a:expr)
            return ['{}']
        endif
        let res = ['{']
        let skeys = sort(keys(a:expr), 's:DictKeyCmp')
        for key in skeys
            let jsonlines = s:PrettyJson(a:expr[key])
            call add(res, s:jsonindent . '"' . key . '": ' . jsonlines[0])
            for jsonline in jsonlines[1:]
                call add(res, s:jsonindent . jsonline)
            endfor
            let res[-1] .= ','
        endfor
        let res[-1] = res[-1][:-2]
        call add(res, '}')
        return res
    else
        throw 'Failed to serialize ' . string(a:expr)
    endif
endfunction

let s:trace_winid = -1
let s:trace_bufnr = -1
let s:term_winid = -1
let s:wince_winid = -1
let s:wince_bufnr = -1
let s:message_winid = -1
let s:message_bufnr = -1

let s:err_winid = -1
let s:err_bufnr = -1
let s:termdiff_winid = -1
let s:wincediff_winid = -1
let s:wincediff_bufnr = -1
let s:messagediff_winid = -1
let s:messagediff_bufnr = -1

function! s:Inspect(linenr)
    if s:trace_bufnr ==# -1
        throw 'No trace loaded'
    endif
    let lines = getbufline(s:trace_bufnr, 1, a:linenr)
    if lines[-1] !=# 'CAP'
        throw 'Cannot inspect at non-capture line ' . lines[-1]
    endif

    let dlines = []
    for line in lines
        call add(dlines, '$$' . line . '$$')
    endfor
    let subtrace = join(dlines, '')
    let capdir = s:sessiondir . '/' . sha256(subtrace)

    if !isdirectory(capdir)
        throw 'No capture found for subtrace ' . subtrace
    endif

    if !filereadable(capdir . '/trace')
        throw 'No trace found'
    endif

    if readfile(capdir . '/trace')[0] !=# subtrace
        throw 'Trace from capture does not match expected'
    endif

    let curwin = win_getid()

    call win_gotoid(s:term_winid)
    set nowrap
    call term_dumpload(capdir . '/screen', {'curwin':1})

    call win_gotoid(s:wince_winid)
    normal! gg
    normal! dG
    let wincemodel = s:PrettyJson(json_decode(readfile(capdir . '/wince')[0]))
    call setbufline(s:wince_bufnr, 1, wincemodel)

    call win_gotoid(s:message_winid)
    normal! gg
    normal! dG
    let messages = readfile(capdir . '/messages')
    call setbufline(s:message_bufnr, 1, messages)

    call win_gotoid(s:trace_winid)
    execute a:linenr
    normal! zz

    call win_gotoid(curwin)
endfunction

function! VimrcTestDebugUp()
    let curwin = win_getid()
    call win_gotoid(s:trace_winid)
    normal! k
    while getline('.') !=# 'CAP' && line('.') !=# 1
        normal! k
    endwhile
    if getline('.') ==# 'CAP'
        call s:Inspect(line('.'))
    endif
    call win_gotoid(curwin)
endfunction

function! VimrcTestDebugDown()
    let curwin = win_getid()
    call win_gotoid(s:trace_winid)
    normal! j
    while getline('.') !=# 'CAP' && line('.') !=# line('$')
        normal! j
    endwhile
    if getline('.') ==# 'CAP'
        call s:Inspect(line('.'))
    endif
    call win_gotoid(curwin)
endfunction

function! VimrcTestDebugLoad(sessiondir)
    if !filereadable(a:sessiondir . '/last')
        throw 'Bad session'
    endif
    let s:sessiondir = a:sessiondir
    let lasthash = readfile(s:sessiondir . '/last')[0]
    let trace = readfile(s:sessiondir . '/' . lasthash . '/trace')[0]
    let steps = []
    while !empty(trace)
        if trace !~# '^\$\$'
            throw 'Bad trace'
        endif
        let [item, itemstartidx, itemendidx] = matchstrpos(
       \    trace,
       \    '^\$\$.\{-}\$\$'
       \)
        let trace = trace[itemendidx:]
        call add(steps, item[2:-3])
    endwhile

    let s:trace_bufnr = bufnr('Session', 1)
    silent buffer Session
    call setbufvar(s:trace_bufnr, '&buftype', 'nofile')
    call setbufvar(s:trace_bufnr, '&swapfile', 0)
    call setbufvar(s:trace_bufnr, '&filetype', 'trace')
    call setbufline(s:trace_bufnr, 1, steps)
    call setbufvar(s:trace_bufnr, '&modifiable', 0)
    call setbufvar(s:trace_bufnr, '&undolevels', -1)
    topleft split
    5wincmd _
    let s:trace_winid = win_getid()

    wincmd w
    vsplit

    let s:term_winid = win_getid()

    wincmd w
    60wincmd |
    let s:wince_bufnr = bufnr('Wince', 1)
    silent buffer Wince
    call setbufvar(s:wince_bufnr, '&buftype', 'nofile')
    call setbufvar(s:wince_bufnr, '&swapfile', 0)
    call setbufvar(s:wince_bufnr, '&filetype', 'json')
    call setbufvar(s:wince_bufnr, '&undolevels', -1)
    split
    let s:wince_winid = win_getid()

    wincmd w
    let s:message_winid = win_getid()
    10wincmd _
    let s:message_bufnr = bufnr('Messages', 1)
    silent buffer Messages
    call setbufvar(s:message_bufnr, '&buftype', 'nofile')
    call setbufvar(s:message_bufnr, '&swapfile', 0)
    call setbufvar(s:message_bufnr, '&filetype', 'text')
    call setbufvar(s:message_bufnr, '&undolevels', -1)

    nnoremap K :silent call VimrcTestDebugUp()<cr>
    nnoremap J :silent call VimrcTestDebugDown()<cr>

    call win_gotoid(s:trace_winid)

    if filereadable(s:sessiondir . '/err')
        call mkdir('difftmp', 'p')

        tabnew
        let errtext = readfile(s:sessiondir . '/err')
        let s:err_bufnr = bufnr('Error', 1)
        silent buffer Error
        call setbufvar(s:err_bufnr, '&buftype', 'nofile')
        call setbufvar(s:err_bufnr, '&swapfile', 0)
        call setbufvar(s:err_bufnr, '&filetype', 'err')
        call setbufline(s:err_bufnr, 1, errtext)
        call setbufvar(s:err_bufnr, '&modifiable', 0)
        call setbufvar(s:err_bufnr, '&undolevels', -1)
        topleft split
        5wincmd _
        let s:err_winid = win_getid()

        wincmd w
        vsplit

        let termdiff_winid = win_getid()

        wincmd w
        60wincmd |
        let s:wincediff_bufnr = bufnr('Wince-Diff', 1)
        silent buffer Wince-Diff
        call setbufvar(s:wincediff_bufnr, '&buftype', 'nofile')
        call setbufvar(s:wincediff_bufnr, '&swapfile', 0)
        call setbufvar(s:wincediff_bufnr, '&filetype', 'diff')
        call setbufvar(s:wincediff_bufnr, '&undolevels', -1)
        split
        let s:wincediff_winid = win_getid()

        wincmd w
        let s:messagediff_winid = win_getid()
        10wincmd _
        let s:messagediff_bufnr = bufnr('Messages-Diff', 1)
        silent buffer Messages-Diff
        call setbufvar(s:messagediff_bufnr, '&buftype', 'nofile')
        call setbufvar(s:messagediff_bufnr, '&swapfile', 0)
        call setbufvar(s:messagediff_bufnr, '&filetype', 'diff')
        call setbufvar(s:messagediff_bufnr, '&undolevels', -1)

        let expdir = 'expect/' . lasthash
        let actdir = s:sessiondir . '/' . lasthash

        call system(
       \    "diff " .
       \    "--new-line-format='+%L' " .
       \    "--old-line-format='-%L' " .
       \    "--unchanged-line-format=' %L' " .
       \    expdir . '/messages ' .
       \    actdir . '/messages ' .
       \    '> difftmp/messages'
       \)
        call setbufline(s:messagediff_bufnr, 1, readfile('difftmp/messages'))

        let expwince = s:PrettyJson(json_decode(readfile(expdir . '/wince')[0]))
        let actwince = s:PrettyJson(json_decode(readfile(actdir . '/wince')[0]))
        call writefile(expwince, 'difftmp/expwince', 's')
        call writefile(actwince, 'difftmp/actwince', 's')

        call system(
       \    "diff " .
       \    "--new-line-format='+%L' " .
       \    "--old-line-format='-%L' " .
       \    "--unchanged-line-format=' %L' " .
       \    'difftmp/expwince ' .
       \    'difftmp/actwince ' .
       \    '> difftmp/wince'
       \)
        call setbufline(s:wincediff_bufnr, 1, readfile('difftmp/wince'))
        call delete('difftmp', 'rf')

        call win_gotoid(termdiff_winid)
        set nowrap
        call term_dumpdiff(actdir . '/screen', expdir . '/screen', {'curwin':1})
    endif

endfunction
