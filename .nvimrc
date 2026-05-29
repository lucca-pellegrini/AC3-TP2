" SPDX-License-Identifier: ISC
" SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

let &runtimepath .= ',' . getcwd() . '/.config/nvim'

augroup local_tomasulo
  autocmd!
  autocmd BufNewFile,BufRead *.tom setfiletype tomasulo
augroup END
