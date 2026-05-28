let &runtimepath .= ',' . getcwd() . '/.config/nvim'

augroup local_tomasulo
  autocmd!
  autocmd BufNewFile,BufRead *.tom setfiletype tomasulo
augroup END
