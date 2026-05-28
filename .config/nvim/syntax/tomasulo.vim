if exists("b:current_syntax")
  finish
endif

" Block keywords
syntax keyword tomBlock cycles units registers instructions

" Opcodes
syntax match tomOpcode /\v<(ADD|SUB|MUL|MULT|DIV|L|S)(\.|_)?D>/
syntax match tomOpcode /\v<(ADDD|SUBD|MULTD|MULD|DIVD|LD|SD)>/

" Registers
syntax match tomRegister /\v<[FR]\d+>/

" Numbers
syntax match tomNumber /\v[-+]?\d+(\.\d+)?([eE][-+]?\d+)?/

" Comments
syntax match tomComment /#.*/
syntax match tomComment /\/\/.*/

" Delimiters
syntax match tomDelimiter /[{}()=]/

" Highlight links
highlight default link tomBlock Keyword
highlight default link tomOpcode Statement
highlight default link tomRegister Identifier
highlight default link tomNumber Number
highlight default link tomComment Comment
highlight default link tomDelimiter Special

let b:current_syntax = "tomasulo"
