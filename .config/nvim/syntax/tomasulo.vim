" SPDX-License-Identifier: ISC
" SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
" NOTE: Vim-like syntax definition written with help from LLMs

if exists("b:current_syntax")
  finish
endif

" Block keywords
syntax keyword tomBlock cycles units registers instructions

" Opcodes
syntax match tomOpcode /\v\c<(ADD|SUB|MUL|MULT|DIV|L|S)(\.|_)?D>/
syntax match tomOpcode /\v\c<(ADDD|SUBD|MULTD|MULD|DIVD|LD|SD)>/

" Registers
syntax match tomRegister /\v\c<[FR]\d+>/

" Numbers
syntax match tomNumber /\v[-+]?\d+(\.\d+)?([eE][-+]?\d+)?/

" Comments
syntax match tomComment /#.*/
syntax match tomComment /\/\/.*/

" Delimiters
syntax match tomDelimiter /[{}()=]/

" Highlight links
highlight default link tomBlock Structure
highlight default link tomOpcode Statement
highlight default link tomRegister Type
highlight default link tomNumber Number
highlight default link tomComment Comment
highlight default link tomDelimiter Delimiter

let b:current_syntax = "tomasulo"
