let s:use_nvim = exists('*nvim_buf_add_highlight')

let s:sgr_search_ptn = '\v\e\[\d+%([;:]\d+)*m'

if s:use_nvim
	if !has_key(s:, 'namespace')
		let s:namespace = nvim_create_namespace('')
	endif
	function! termescape#add_hl(kw)
		let l:buf = bufnr(a:kw.buffer)
		let l:grp = a:kw.group
		let l:ln = a:kw.line
		let l:start = a:kw.start
		let l:end = a:kw.end
		call nvim_buf_add_highlight(l:buf, s:namespace, l:grp, l:ln - 1,
			\ l:start - 1, l:end - 1)
		let a:kw.chwin = 0
		let a:kw.dirty = 0
	endfunction
	function! termescape#update_hl(kw)
		let a:kw.chwin = 0
		let a:kw.dirty = 0
	endfunction
	function! termescape#del_hl_lines(buf, line_start, line_end, handles)
		call nvim_buf_clear_namespace(bufnr(a:buf), s:namespace, a:line_start, a:line_end)
	endfunction
else
	function! termescape#add_hl(kw)
		let l:buf = bufnr(a:kw.buffer)
		let l:grp = a:kw.group
		let l:ln = a:kw.line
		let l:start = a:kw.start
		let l:len = a:kw.end - l:start
		let l:win = win_getid()
		let l:opts = {}
		if bufnr('') != l:buf
			let l:win = get(a:kw, 'window', bufwinid(l:buf))
			let l:opts.window = l:win
		else
			let l:win = get(a:kw, 'window', l:win)
		endif
		let a:kw.window = l:win
		let a:kw.id = matchaddpos(l:grp, [[l:ln, l:start, l:len]],
			\ 10, -1, l:opts)
		let a:kw.chwin = 0
		let a:kw.dirty = 0
	endfunction
	function! termescape#update_hl(kw)
		let l:grp = a:kw.group
		let l:ln = a:kw.line
		let l:start = a:kw.start
		let l:len = a:kw.end - l:start
		if has("patch-8.1.0218") || has("patch8.1.0218")
			call matchdelete(a:kw.id, a:kw.window)
		else
			call matchdelete(a:kw.id)
		endif
		if a:kw.chwin
			let a:kw.id = -1
			let a:kw.window = a:kw.new_window
		endif
		let l:opts = {'window': a:kw.window}
		let a:kw.id = matchaddpos(l:grp, [[l:ln, l:start, l:len]],
			\ 10, a:kw.id, l:opts)
		let a:kw.chwin = 0
		let a:kw.dirty = 0
	endfunction
	function! termescape#del_hl_lines(buf, line_start, line_end, handles)
		for l:line in a:handles
			for l:kw in l:line
				if has("patch-8.1.0218")
					call matchdelete(l:kw.id, l:kw.window)
				else
					call matchdelete(l:kw.id)
				endif
			endfor
		endfor
	endfunction
endif

function! s:equals(x, y)
	if type(a:x) != type(a:y)
		return v:false
	endif
	return a:x == a:y
endfunction

function! termescape#get_buf_or_global_var(buf, name, default)
	let l:g = get(g:, a:name, a:default)
	return getbufvar(a:buf, a:name, l:g)
endfunction

let s:default_opts = {
	\ 'cterm_depth': [8, 4],
	\ 'gui_depth': [24, 8],
	\ 'cterm_styles': ['bold', 'italic', 'underline', 'reverse'],
	\ 'gui_styles': ['bold', 'italic', 'underline', 'reverse', 'strikethrough'],
	\ 'cterm_use_terminal_colors': 0,
	\ 'gui_use_terminal_colors': 1,
	\ 'detect_styles': ['bg', 'fg', 'bold', 'italic', 'underline', 'reverse', 'strikethrough'],
	\ 'process_entire': 1,
	\ 'handle_change': 1,
	\ 'lines_before_change': 2,
	\ 'lines_after_change': 5,
	\ }
function! s:extract_options(opts, keys)
	let l:buf = get(a:opts, 'buffer', '')
	let l:new_opts = {}
	for l:k in a:keys
		if l:k == 'buffer'
			let l:new_opts[l:k] = l:buf
		elseif has_key(a:opts, l:k)
			let l:new_opts[l:k] = a:opts[l:k]
		else
			let l:new_opts[l:k] = termescape#get_buf_or_global_var(
				\ l:buf, 'termescape_' . l:k,
				\ get(s:default_opts, l:k))
		endif
	endfor
	return l:new_opts
endfunction

function! termescape#match_all(str, ptn)
	let l:lst = []
	let l:end = 0
	while v:true
		let l:start = match(a:str, a:ptn, l:end)
		if l:start < 0
			break
		endif
		let l:end = matchend(a:str, a:ptn, l:start)
		let l:lst = add(l:lst, [l:start, l:end])
	endwhile
	return l:lst
endfunction

function! termescape#sgr_extract_numbers(sgr)
	return map(split(a:sgr[2 : -2], '[;:]', v:true), 'str2nr(v:val)')
endfunction

function! termescape#sgr_interpret_numbers(lst)
	if len(a:lst) == 0
		return {'reset': 1}
	endif
	let l:styles = {}
	let l:i = 0
	while l:i < len(a:lst)
		let l:c = a:lst[l:i]
		if l:c == 0
			let l:styles = {'reset': 1}
		elseif l:c == 1
			let l:styles.bold = 1
		elseif l:c == 3
			let l:styles.italic = 1
		elseif l:c == 4
			let l:styles.underline = 1
			" '4:n' is used in vte for different underlines
			if len(a:lst) == 2 && l:i == 0 && a:lst[1] < 6
				let l:styles.underline = a:lst[1]
				break
			endif
		elseif l:c == 5
			let l:styles.blink = 1
		elseif l:c == 7
			let l:styles.reverse = 1
		elseif l:c == 8
			let l:styles.invisible = 1
		elseif l:c == 9
			let l:styles.strikethrough = 1
		elseif l:c == 21 || l:c == 22
			let l:styles.bold = 0
		elseif l:c == 23
			let l:styles.italic = 0
		elseif l:c == 24
			let l:styles.underline = 0
		elseif l:c == 25
			let l:styles.blink = 0
		elseif l:c == 27
			let l:styles.reverse = 0
		elseif l:c == 28
			let l:styles.invisible = 0
		elseif l:c == 29
			let l:styles.strikethrough = 0
		elseif (l:c >= 30 && l:c <= 37) || (l:c >= 90 && l:c <= 97)
			if l:c > 50
				let l:c -= 52
			endif
			let l:c -= 30
			let l:styles.fg = l:c
		elseif (l:c >= 40 && l:c <= 47) || (l:c >= 100 && l:c <= 107)
			if l:c > 50
				let l:c -= 52
			endif
			let l:c -= 40
			let l:styles.bg = l:c
		elseif l:c == 39
			let l:styles.fg = -1
		elseif l:c == 49
			let l:styles.bg = -1
		elseif l:c == 38
			try
				let l:i += 1
				let l:type = a:lst[l:i]
				if l:type == 5
					let l:i += 1
					let l:styles.fg = a:lst[l:i]
				elseif l:type == 2
					let l:i += 1
					let l:color = a:lst[l:i : l:i + 2]
					let l:i += 3
					if len(l:color) == 3
						let l:styles.fg = l:color
					endif
				endif
			catch /^Vim\%((\a\+)\)\=:E684/
				break
			endtry
		elseif l:c == 48
			try
				let l:i += 1
				let l:type = a:lst[l:i]
				if l:type == 5
					let l:i += 1
					let l:styles.bg = a:lst[l:i]
				elseif l:type == 2
					let l:i += 1
					let l:color = a:lst[l:i : l:i + 2]
					let l:i += 3
					if len(l:color) == 3
						let l:styles.bg = l:color
					endif
				endif
			catch /^Vim\%((\a\+)\)\=:E684/
				break
			endtry
		elseif l:c == 58
			" Reserved, used in vte to set undeline color
			break
		elseif l:c == 59
			" Reserved, used in vte to reset undeline color
			break
		endif
		let l:i += 1
	endwhile
	return l:styles
endfunction

function! termescape#update_styles(old, new)
	if get(a:new, 'reset', 0)
		return copy(a:new)
	endif
	let l:result = copy(a:old)
	for l:k in keys(a:new)
		let l:result[l:k] = a:new[l:k]
	endfor
	return l:result
endfunction

let s:intensities = [0x00, 0x66, 0x88, 0xBB, 0xDD, 0xFF]
function! termescape#color8to24(num)
	let l:num = a:num
	if l:num < 0
		return l:num
	endif
	if l:num < 16
		let l:lst = [0, 0, 0]
		if l:num >= 8
			let l:lst = [0x55, 0x55, 0x55]
			let l:num -= 8
		endif
		if l:num >= 4
			let l:lst[2] += 0xAA
			let l:num -= 4
		endif
		if l:num >= 2
			let l:lst[1] += 0xAA
			let l:num -= 2
		endif
		if l:num >= 1
			let l:lst[0] += 0xAA
			let l:num -= 1
		endif
		return l:lst
	endif
	if l:num >= 232
		let l:num -= 232
		return 8 + 10 * l:num
	endif
	let l:num -= 16
	let l:b = l:num % 6
	let l:num /= 6
	let l:g = l:num % 6
	let l:num /= 6
	let l:r = l:num % 6
	return [s:intensities[l:r], s:intensities[l:g], s:intensities[l:b]]
endfunction

function! s:MAE(x, y)
	let l:s = 0
	for l:i in range(len(a:x))
		let l:s += abs(a:x[l:i] - a:y[l:i])
	endfor
	return l:s / len(a:x)
endfunction

function! termescape#color24to4(lst)
	let l:lst = copy(a:lst)
	let l:lst_int = [0, 0, 0]
	for l:i in [0, 1, 2]
		let l:lst[l:i] = l:lst[l:i] / 0x55
		let l:lst_round[l:i] = float2nr(round(l:lst[l:i]))
	endfor
	" TODO better mapping
	let l:w = (l:lst[0] + l:lst[1] + l:lst[2]) % 2
	for l:i in [0, 1, 2]
		let l:lst[l:i] -= l:w
	endfor
	for l:i in [0, 1, 2]
		let l:lst_int[l:i] = l:lst[l:i] >= 1.5 ? 1 : 0
	endfor
	return l:w * 8 + l:lst_int[0] * 1 + l:lst_int[1] * 2 + l:lst_int[3] * 4
endfunction

function! termescape#color24to8(lst)
	let l:lst = copy(a:lst)
	for l:i in [0, 1, 2]
		let l:c = l:lst[l:i]
		if l:c < 0x33
			let l:c = 0
		elseif l:c < 0x77
			let l:c = 1
		elseif l:c < 0xA1
			let l:c = 2
		elseif l:c < 0xCC
			let l:c = 3
		elseif l:c < 0xEE
			let l:c = 4
		else
			let l:c = 5
		endif
		let l:lst[l:i] = l:c
	endfor
	if l:lst[0] == l:lst[1] && l:lst[1] == l:lst[2]
		let l:avg = (a:lst[0] + a:lst[1] + a:lst[2]) / 3
		if l:avg > 4 && l:avg < 247
			return min([255, float2nr((l:avg - 4) / 10) + 232])
		endif
	endif
	return 36 * l:lst[0] + 6 * l:lst[1] + l:lst[2] + 16
endfunction

function! termescape#color24to4or8(lst)
	let l:c4 = termescape#color24to4(a:lst)
	let l:c8 = termescape#color24to8(a:lst)
	let l:e4 = s:MAE(termescape#color8to24(l:c4), a:lst)
	let l:e8 = s:MAE(termescape#color8to24(l:c8), a:lst)
	return l:e4 < l:e8 ? l:c4 : l:c8
endfunction

function! termescape#color_to_str(color)
	if type(a:color) == 1
		" String
		return a:color
	endif
	if type(a:color) == 3
		" Array
		return printf('#%02x%02x%02x', a:color[0], a:color[1], a:color[2])
	endif
	if a:color < 0
		return 'NONE'
	endif
	return printf('%d', a:color)
endfunction

function! termescape#color_to_depth(color, depths)
	if type(a:color) == 0 && a:color < 0
		return a:color
	endif
	if type(a:depths) == 0
		return termescape#color_to_depth(a:color, [a:depths])
	endif
	if len(a:depths) == 0
		return a:color
	endif
	if type(a:color) == 0
		" 4 or 8 bit
		if a:color < 16
			if index(a:depths, 4) >= 0
				return a:color
			endif
		elseif index(a:depths, 8) >= 0
			return a:color
		endif
		let l:c24 = termescape#color8to24(a:color)
		if a:depths[0] < 8
			return termescape#color24to4(l:c24)
		endif
		if a:depths[0] < 24
			return termescape#color24to8(l:c24)
		endif
		return l:c24
	else
		" 24 bit
		if index(a:depths, 24) >= 0
			return copy(a:color)
		endif
		if a:depths[0] > 4
			return termescape#color24to8(a:color)
		endif
		if index(a:depths, 8) >= 0
			return termescape#color24to4or8(a:color)
		endif
		return termescape#color24to4(a:color)
	endif
	throw 'Argument error'
endfunction

function! termescape#color_to_depth_str(color, depths, use_terminal_colors)
	if type(a:depths) == 0
		return termescape#color_to_depth_str(a:color, [a:depths])
	endif
	if a:use_terminal_colors
		if type(a:color) == 0 && a:color < 16 && index(a:depths, 4) < 0
			let l:varname = 'terminal_color_' . a:color
			if has_key(g:, l:varname)
				return g:[l:varname]
			endif
		endif
	endif
	let l:c = termescape#color_to_depth(a:color, a:depths)
	return termescape#color_to_str(l:c)
endfunction

let s:style_abbrs = {
	\ 'bold': 'b',
	\ 'italic': 'i',
	\ 'underline': 'u',
	\ 'blink': 'B',
	\ 'reverse': 'r',
	\ 'invisible': 'h',
	\ 'strikethrough': 's',
	\ }
function! termescape#compare_styles(old, new, keys)
	let l:changed = v:false
	let l:filtered = {}
	let l:name = ''
	for l:k in ['bold', 'italic', 'underline', 'blink', 'reverse', 'invisible', 'strikethrough']
		if index(a:keys, l:k) < 0
			continue
		endif
		let l:new_value = get(a:new, l:k)
		if get(a:old, l:k) != l:new_value
			let l:changed = v:true
		endif
		if l:new_value
			let l:name .= s:style_abbrs[l:k]
		endif
		let l:filtered[l:k] = l:new_value
	endfor
	for l:k in ['bg', 'fg']
		let l:new_value = get(a:new, l:k, -1)
		if index(a:keys, l:k) < 0
			let l:new_value = -1
		endif
		let l:cname = termescape#color_to_depth_str(l:new_value, [24], 0)
		if l:cname[0] == '#'
			let l:cname = l:cname[1:]
		endif
		let l:name .= '_' . l:cname
		if index(a:keys, l:k) < 0
			continue
		endif
		if !s:equals(get(a:old, l:k), l:new_value)
			let l:changed = v:true
		endif
		let l:filtered[l:k] = l:new_value
	endfor
	return {
		\ 'changed': l:changed,
		\ 'name': l:name,
		\ 'filtered_styles': l:filtered,
		\ }
endfunction

function! s:format_hl_group(name)
	return 'termescapeStyle_' . a:name
endfunction

let s:already_highlighted = {}
function! termescape#ensure_highlighting(name, styles, options)
	if get(s:already_highlighted, a:name)
		return
	endif
	let l:opts = s:extract_options(a:options, [
		\ 'cterm_depth', 'gui_depth', 'cterm_styles', 'gui_styles',
		\ 'cterm_use_terminal_colors', 'gui_use_terminal_colors'])
	let l:decor_cterm = []
	let l:decor_gui = []
	for l:k in ['bold', 'italic', 'underline', 'reverse']
		if !get(a:styles, l:k)
			continue
		endif
		if index(l:opts.cterm_styles, l:k) >= 0
			let l:decor_cterm = add(l:decor_cterm, l:k)
		endif
		if index(l:opts.gui_styles, l:k) >= 0
			let l:decor_gui = add(l:decor_gui, l:k)
		endif
	endfor
	let l:colors = {}
	for l:client in ['cterm', 'gui']
		for l:part in ['bg', 'fg']
			let l:colors[l:client . l:part] =
				\ termescape#color_to_depth_str(
				\ get(a:styles, l:part, -1),
				\ l:opts[l:client . '_depth'],
				\ l:opts[l:client . '_use_terminal_colors'])
		endfor
	endfor
	exe 'hi ' . s:format_hl_group(a:name) . 
		\ (len(l:decor_cterm) ? ' cterm=' . join(l:decor_cterm, ',') : '') .
		\ (len(l:decor_gui)   ?   ' gui=' . join(l:decor_gui,   ',') : '') .
		\ ' ctermbg=' . l:colors['ctermbg'] .
		\   ' guibg=' . l:colors[  'guibg'] .
		\ ' ctermfg=' . l:colors['ctermfg'] .
		\   ' guifg=' . l:colors[  'guifg']
	let s:already_highlighted[a:name] = 1
endfunction

function! termescape#invalidate_highlighting()
	let s:already_highlighted = {}
endfunction

function! termescape#parse_lines(lines, init_styles, options)
	let l:styles = a:init_styles
	let l:opts = s:extract_options(a:options, ['detect_styles'])
	let l:regions = []
	let l:group_styles = {}
	let l:end_styles = []

	let l:lnnum = -1
	for l:ln in a:lines
		let l:lnnum += 1

		let l:diff = termescape#compare_styles({}, l:styles, l:opts.detect_styles)
		if l:diff.changed
			let l:group_styles[l:diff.name] = l:diff.filtered_styles
			call add(l:regions, {'line': l:lnnum, 'start': 0, 'name': l:diff.name})
		endif

		for l:match in termescape#match_all(l:ln, s:sgr_search_ptn)
			let l:sgr = l:ln[l:match[0] : l:match[1]]
			let l:nums = termescape#sgr_extract_numbers(l:sgr)
			let l:new_styles = termescape#sgr_interpret_numbers(l:nums)
			let l:new_styles = termescape#update_styles(l:styles, l:new_styles)
			let l:diff = termescape#compare_styles(l:styles, l:new_styles, l:opts.detect_styles)
			let l:styles = l:new_styles
			if !l:diff.changed
				continue
			endif
			let l:group_styles[l:diff.name] = l:diff.filtered_styles
			if len(l:regions) && l:regions[-1].line == l:lnnum
				let l:prev = l:regions[-1]
				if l:prev.start == l:match[0]
					call remove(l:regions, -1)
				else
					let l:prev.end = l:match[0]
				endif
			endif
			call add(l:regions, {'line': l:lnnum, 'start': l:match[1], 'name': l:diff.name})
		endfor
		let l:end = len(l:ln)
		if len(l:regions) && l:regions[-1].line == l:lnnum
			let l:prev = l:regions[-1]
			if l:prev.start == l:end
				call remove(l:regions, -1)
			else
				let l:prev.end = l:end
			endif
		endif
		call add(l:end_styles, l:styles)
	endfor
	return {
		\ 'end_styles': l:end_styles,
		\ 'regions': l:regions,
		\ 'group_styles': l:group_styles,
		\ }
endfunction

function! s:get_end_styles(buf)
	let l:vars = getbufinfo(a:buf)[0].variables
	if has_key(l:vars, 'end_styles')
		return l:vars.end_styles
	endif
	let l:vars.end_styles = {0: {}}
	return l:vars.end_styles
endfunction

function! termescape#rehighlight_range(buf, line1, line2)
	let l:highlights = getbufvar(a:buf, 'termescape_highlights', 0)
	if type(l:highlights) == 0
		let l:highlights = {}
		call setbufvar(a:buf, 'termescape_highlights', l:highlights)
	endif
	let l:range_highlights = []
	for l:i in range(a:line1, a:line2)
		if has_key(l:highlights, l:i)
			let l:range_highlights = add(l:range_highlights, l:highlights[l:i])
		else
			let l:lst = []
			let l:range_highlights = add(l:range_highlights, l:lst)
			let l:highlights[l:i] = l:lst
		endif
	endfor
	" TODO options
	let l:end_styles = s:get_end_styles(a:buf)
	let l:init_styles = get(l:end_styles, a:line1 - 1, {})
	let l:parsed = termescape#parse_lines(getbufline(a:buf, a:line1, a:line2), l:init_styles, {})
	call termescape#del_hl_lines(a:buf, a:line1, a:line2, l:range_highlights)
	for l:i in range(a:line1, a:line2)
		let l:lst = []
		let l:range_highlights[l:i - a:line1] = l:lst
		let l:highlights[l:i] = l:lst
		let l:end_styles[l:i] = l:parsed.end_styles[l:i - a:line1]
	endfor
	for l:reg in l:parsed.regions
		let l:name = l:reg.name
		call termescape#ensure_highlighting(l:name, l:parsed.group_styles[l:name], {})
		let l:kw = {
			\ 'buffer': a:buf,
			\ 'group': s:format_hl_group(l:name),
			\ 'line': l:reg.line + a:line1,
			\ 'start': l:reg.start + 1,
			\ 'end': l:reg.end + 1,
			\ }
		call termescape#add_hl(l:kw)
		call add(l:range_highlights[l:reg.line], l:kw)
	endfor
endfunction

function! termescape#unhighlight_range(buf, line1, line2)
	let l:highlights = getbufvar(a:buf, 'termescape_highlights', 0)
	if type(l:highlights) == 0
		let l:highlights = {}
		call setbufvar(a:buf, 'termescape_highlights', l:highlights)
	endif
	let l:range_highlights = []
	for l:i in range(a:line1, a:line2)
		if has_key(l:highlights, l:i)
			let l:range_highlights = add(l:range_highlights, l:highlights[l:i])
		else
			let l:lst = []
			let l:range_highlights = add(l:range_highlights, l:lst)
			let l:highlights[l:i] = l:lst
		endif
	endfor
	call termescape#del_hl_lines(a:buf, a:line1, a:line2, l:range_highlights)
	for l:i in range(a:line1, a:line2)
		let l:highlights[l:i] = []
	endfor
endfunction

function! termescape#handle_change(line1, line2, options)
	let l:opts = s:extract_options(a:options, ['handle_change', 'lines_before_change', 'lines_after_change'])
	if !l:opts.handle_change
		return
	endif
	let l:line1 = a:line1 - l:opts.lines_before_change 
	let l:line2 = a:line2 + l:opts.lines_after_change 
	call termescape#rehighlight_range('', max([l:line1, 1]), min([l:line2, line('$')]))
endfunction

function! termescape#enable_for_buffer(options)
	let l:opts = s:extract_options(a:options, ['process_entire', 'handle_change'])
	if l:opts.handle_change && !get(b:, 'termescape_au_registered')
		aug termescape_change_handler
			au TextChanged,InsertLeave <buffer> call termescape#handle_change(line("'["), line("']"), {})
		aug END
	endif
	if l:opts.process_entire
		call termescape#rehighlight_range('', 1, line('$'))
	endif
endfunction
