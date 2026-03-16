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
command! SqlLensDB           lua require('sql-lens').pick_database()
command! SqlLensTables       lua require('sql-lens').explore_tables()
command! SqlLensHistory      lua require('sql-lens').show_history()
command! SqlLensSaveConn     lua require('sql-lens.bookmarks').pick_and_save()
command! -nargs=1 SqlLensExport lua require('sql-lens.ui.result').export(<q-args>)
command! SqlLensFormat        lua require('sql-lens.formatter').format_buffer()
command! SqlLensSchemaDiff    lua require('sql-lens.schema_diff').pick_and_compare()
command! SqlLensCostTrend     lua require('sql-lens').show_cost_trend()
command! SqlLensER            lua require('sql-lens.er_diagram').generate()
command! SqlLensColumns       lua require('sql-lens.column_picker').pick()
command! SqlLensSnippets      lua require('sql-lens.snippets').pick()
command! SqlLensResultDiff    lua require('sql-lens').result_diff_current()
command! SqlLensChart         lua require('sql-lens.chart').show()
command! SqlLensDashboard     lua require('sql-lens.dashboard').show()
command! SqlLensDepGraph      lua require('sql-lens.dep_graph').generate()
command! -nargs=1 SqlLensUse lua require('sql-lens').use_connection(<q-args>)

augroup SqlLens
  autocmd!
  autocmd FileType sql,plpgsql lua require('sql-lens').attach_buffer()
augroup END
