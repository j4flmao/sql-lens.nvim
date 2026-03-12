if exists('g:loaded_sql_lens') | finish | endif
let g:loaded_sql_lens = 1

command! SqlLensConnect      lua require('sql-lens').connect()
command! SqlLensDisconnect   lua require('sql-lens').disconnect()
command! SqlLensToggle       lua require('sql-lens').toggle()
command! SqlLensExplain      lua require('sql-lens').explain_current()
command! SqlLensFloatDetail  lua require('sql-lens').show_detail()
command! SqlLensRun          lua require('sql-lens').run_current()
command! -range SqlLensRunSelection lua require('sql-lens').run_selection()
command! SqlLensRunAll       lua require('sql-lens').run_all()
command! SqlLensReport       lua require('sql-lens').report()
command! -nargs=1 SqlLensUse lua require('sql-lens').use_connection(<q-args>)

augroup SqlLens
  autocmd!
  autocmd FileType sql,plpgsql lua require('sql-lens').attach_buffer()
augroup END
