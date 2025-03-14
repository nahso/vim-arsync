" Vim plugin to handle async rsync synchronisation between hosts
" Title: vim-arsync
" Author: Ken Hasselmann
" Date: 08/2019
" License: MIT

let g:vim_arsync_latest_upload_job_id = -1
let g:vim_arsync_post_upload_script = ''
let g:vim_arsync_need_invoke = 0
let g:vim_arsync_job_running = 0

function! g:PostArsyncScript()
  if g:vim_arsync_job_running
    let g:vim_arsync_need_invoke = 1
else
    if g:vim_arsync_post_upload_script != ''
        call system('bash ' . shellescape(g:vim_arsync_post_upload_script) . ' &')
        let g:vim_arsync_need_invoke = 0
        echo "vim-arsync post upload script invoked."
    endif
  endif
endfunction

function! LoadConf()
    let l:conf_dict = {}
    let l:file_exists = filereadable('.vim-arsync')

    if l:file_exists > 0
        let l:conf_options = readfile('.vim-arsync')
        for i in l:conf_options
            let l:var_name = substitute(i[0:stridx(i, ' ')], '^\s*\(.\{-}\)\s*$', '\1', '')
            if l:var_name == 'ignore_path' || l:var_name == 'include_path'
                let l:var_value = eval(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''))
                " echo substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', '')
            elseif l:var_name == 'remote_passwd'
                " Do not escape characters in passwords.
                let l:var_value = substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', '')
            else
                let l:var_value = escape(substitute(i[stridx(i, ' '):], '^\s*\(.\{-}\)\s*$', '\1', ''), '%#!')
            endif
            let l:conf_dict[l:var_name] = l:var_value
        endfor
    endif
    if has_key(l:conf_dict, "auto_sync_up") && has_key(l:conf_dict, "auto_sync_down")
        if l:conf_dict['auto_sync_up'] == 1 && l:conf_dict['auto_sync_down'] == 1
            echoerr 'You cannot have both auto_sync_up and auto_sync_down enabled at the same time. Aborting...'
            return
        endif
    endif
    if !has_key(l:conf_dict, "local_path")
        let l:conf_dict['local_path'] = getcwd()
    endif
    if !has_key(l:conf_dict, "remote_port")
        let l:conf_dict['remote_port'] = 22
    endif
    if !has_key(l:conf_dict, "remote_or_local")
        let l:conf_dict['remote_or_local'] = "remote"
    endif
    if !has_key(l:conf_dict, "local_options")
        let l:conf_dict['local_options'] = "-var"
    endif
    if !has_key(l:conf_dict, "remote_options")
        let l:conf_dict['remote_options'] = "-vazre"
    endif
    if has_key(l:conf_dict, "post_upload_script")
        let g:vim_arsync_post_upload_script = expand(l:conf_dict['post_upload_script'])
    endif
    return l:conf_dict
endfunction

function! JobHandler(job_id, data, event_type)
    if a:event_type == 'exit'
        if a:data != 0
            echo "vim-arsync failed."
        endif
        if a:data == 0
            echo "vim-arsync success."
            let g:vim_arsync_job_running = 0
            if g:vim_arsync_post_upload_script != '' && g:vim_arsync_need_invoke == 1
                call system('bash ' . shellescape(g:vim_arsync_post_upload_script) . ' &')
                let g:vim_arsync_need_invoke = 0
                echo "vim-arsync post upload script invoked."
            endif
        endif
        " echom string(a:data)
    endif
endfunction

function! ShowConf()
    let l:conf_dict = LoadConf()
    echo l:conf_dict
    echom string(getqflist())
endfunction

function! ARsync(direction)
    let l:conf_dict = LoadConf()
    if has_key(l:conf_dict, 'remote_host')
        let l:user_passwd = ''
        if has_key(l:conf_dict, 'remote_user')
            let l:user_passwd = l:conf_dict['remote_user'] . '@'
            if has_key(l:conf_dict, 'remote_passwd')
                if !executable('sshpass')
                    echoerr 'You need to install sshpass to use plain text password, otherwise please use ssh-key auth.'
                    return
                endif
                let sshpass_passwd = l:conf_dict['remote_passwd']
            endif
        endif
        if l:conf_dict['remote_or_local'] == 'remote'
            if a:direction == 'down'
                let l:cmd = [ 'rsync', l:conf_dict['remote_options'], 'ssh -p '.l:conf_dict['remote_port'], l:user_passwd . l:conf_dict['remote_host'] . ':' . l:conf_dict['remote_path'] . '/', l:conf_dict['local_path'] . '/']
            elseif  a:direction == 'up'
                let l:cmd = [ 'rsync', l:conf_dict['remote_options'], 'ssh -p '.l:conf_dict['remote_port'], l:conf_dict['local_path'] . '/', l:user_passwd . l:conf_dict['remote_host'] . ':' . l:conf_dict['remote_path'] . '/']
            else " updelete
                let l:cmd = [ 'rsync', l:conf_dict['remote_options'], 'ssh -p '.l:conf_dict['remote_port'], l:conf_dict['local_path'] . '/', l:user_passwd . l:conf_dict['remote_host'] . ':' . l:conf_dict['remote_path'] . '/', '--delete']
            endif
        elseif l:conf_dict['remote_or_local'] == 'local'
            if a:direction == 'down'
                let l:cmd = [ 'rsync', l:conf_dict['local_options'],  l:conf_dict['remote_path'] , l:conf_dict['local_path']]
            elseif  a:direction == 'up'
                let l:cmd = [ 'rsync', l:conf_dict['local_options'],  l:conf_dict['local_path'] , l:conf_dict['remote_path']]
            else " updelete
                let l:cmd = [ 'rsync', l:conf_dict['local_options'],  l:conf_dict['local_path'] , l:conf_dict['remote_path'] . '/', '--delete']
            endif
        endif
        if has_key(l:conf_dict, 'ignore_path')
            for file in l:conf_dict['ignore_path']
                let l:cmd = l:cmd + ['--exclude', file]
            endfor
        endif
        if has_key(l:conf_dict, 'include_path')
            for file in l:conf_dict['include_path']
                let l:cmd = l:cmd + ['--include', file]
            endfor
        endif
        if has_key(l:conf_dict, 'ignore_dotfiles')
            if l:conf_dict['ignore_dotfiles'] == 1
                let l:cmd = l:cmd + ['--exclude', '.*']
            endif
        endif
        if has_key(l:conf_dict, 'remote_passwd')
            let l:cmd = ['sshpass', '-p', sshpass_passwd] + l:cmd
        endif

        if g:vim_arsync_latest_upload_job_id != -1
            try
                call async#job#stop(g:vim_arsync_latest_upload_job_id)
            catch
                " Job might have completed already
            endtry
        endif

        " create qf for job
        call setqflist([], ' ', {'title' : 'vim-arsync'})
        let g:qfid = getqflist({'id' : 0}).id
        " redraw | echom join(cmd)
        let g:vim_arsync_job_running = 1
        let g:vim_arsync_latest_upload_job_id = async#job#start(cmd, {
                    \ 'on_stdout': function('JobHandler'),
                    \ 'on_stderr': function('JobHandler'),
                    \ 'on_exit': function('JobHandler'),
                    \ })
        " TODO: handle errors
    else
        echoerr 'Could not locate a .vim-arsync configuration file. Aborting...'
    endif
endfunction

function! AutoSync()
    let l:conf_dict = LoadConf()
    if has_key(l:conf_dict, 'auto_sync_up')
        if l:conf_dict['auto_sync_up'] == 1
            if has_key(l:conf_dict, 'sleep_before_sync')
                let g:sleep_time = l:conf_dict['sleep_before_sync']*1000
                autocmd BufWritePost,FileWritePost * call timer_start(g:sleep_time, { -> execute("call ARsync('up')", "")})
            else
                autocmd BufWritePost,FileWritePost * ARsyncUp
            endif
            " echo 'Setting up auto sync to remote'
        endif
    endif
endfunction

if !executable('rsync')
    echoerr 'You need to install rsync to be able to use the vim-arsync plugin'
    finish
endif

command! ARsyncUp call ARsync('up')
command! ARsyncUpDelete call ARsync('upDelete')
command! ARsyncDown call ARsync('down')
command! ARshowConf call ShowConf()

augroup vimarsync
    autocmd!
    autocmd VimEnter * call AutoSync()
    autocmd DirChanged * call AutoSync()
augroup END
