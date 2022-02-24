" Vim syntax file
if !exists("main_syntax")
  if version < 600
    syntax clear
  elseif exists("b:current_syntax")
    finish
  endif
  let main_syntax = 'termescape'
endif

if version < 508
  command! -nargs=+ TermescapeHiLink highlight link <args>
else
  command! -nargs=+ TermescapeHiLink highlight default link <args>
endif

syn region termescapeControlSequence matchgroup=termescapeCSI start=/\v\e\[/ matchgroup=termescapeControlFinal end=/\v[@A-Z\[\\\]\^_`a-z\{\|\}~]/ contains=termescapeControlParameters,termescapeControlIntermediate conceal

syn match termescapeControlParameters /\v[0-9:;\<\=\>\?]+/ contained
syn match termescapeControlIntermediate /\v[ !"#\$\%&'()*+,-.\/]+/ contained

TermescapeHiLink termescapeControlSequence Error
TermescapeHiLink termescapeCSI PreProc
TermescapeHiLink termescapeControlFinal PreProc
TermescapeHiLink termescapeControlParameters Constant
TermescapeHiLink termescapeControlIntermediate Special

delcommand TermescapeHiLink

let b:current_syntax = "termescape"
if main_syntax ==# 'termescape'
  unlet main_syntax
endif
