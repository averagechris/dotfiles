" --- the plugins are between the call plug begin and end
call plug#begin('~/.vim/plugged')

Plug 'bronson/vim-trailing-whitespace'
Plug 'SirVer/ultisnips', { 'on': [] } | Plug 'honza/vim-snippets'
Plug 'Valloric/YouCompleteMe', { 'on': [] }
Plug 'rdnetto/YCM-Generator', { 'branch': 'stable'}
Plug 'tpope/vim-surround'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'tpope/vim-fugitive'

" Swift syntax and indent files
Plug 'keith/swift.vim'

" syntastic
Plug 'https://github.com/scrooloose/syntastic.git'
" uses the local eslint install
Plug 'mtscout6/syntastic-local-eslint.vim'

" vim-go
Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries' }
" vim-go has some commands that depend on ctrlp
Plug 'ctrlpvim/ctrlp.vim'

call plug#end()

" -- ultisnips / youcompleteme config
augroup load_us_ycm
	autocmd!
	autocmd InsertEnter * call plug#load('ultisnips', 'YouCompleteMe')
			\| autocmd! load_us_ycm
augroup END
let g:ycm_autoclose_preview_window_after_completion=1
nnoremap <leader>g :YcmCompleter GoToDefinitionElseDeclaration<CR>

" UltiSnips triggering
let g:UltiSnipsExpandTrigger = '<S-j>'
let g:UltiSnipsJumpForwardTrigger = '<S-j>'
let g:UltiSnipsJumpBackwardTrigger = '<S-k>'

" syntastic config
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_loc_list_height = 5
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 1
let g:syntastic_javascript_checkers = ['eslint']

let g:syntastic_error_symbol = 'X'
let g:syntastic_style_error_symbol = '!'
let g:syntastic_warning_symbol = 'W'
let g:syntastic_style_warning_symbol = 'S'

highlight link SyntasticErrorSign SignColumn
highlight link SyntasticWarningSign SignColumn
highlight link SyntasticStyleErrorSign SignColumn
highlight link SyntasticStyleWarningSign SignColumn

" -- status line config
set laststatus=2
set noshowmode
let g:airline_theme='serene'
let g:airline#extensions#tabline#enabled = 1


" -- VIM-GO config
let g:go_fmt_command = "goimports"
let g:go_metalinter_autosave = 1
let g:go_metalinter_autosave_enabled = ['vet', 'golint']
" let g:go_auto_sameids = 1 " this highlights matching declarations and I think I hate it
" these autocmd are like short cuts for moving between files
autocmd Filetype go command! -bang A call go#alternate#Switch(<bang>0, 'edit')
autocmd Filetype go command! -bang AV call go#alternate#Switch(<bang>0, 'vsplit')
autocmd Filetype go command! -bang AS call go#alternate#Switch(<bang>0, 'split')
" prevent issues with syntastic
let g:syntastic_go_checkers = ['golint', 'govet', 'errcheck']
let g:syntastic_mode_map = { 'mode': 'active', 'passive_filetypes': ['go'] }
let g:go_list_type = "quickfix"

" -- ctr-p config
set wildignore+=*/.git/*,*/node_modules/*  " -- hide .git, node_modules

" -- LOOK AND FEEL
set background=dark
set nocompatible
filetype on
syntax enable  " enable syntax processing
set number  " set line numbers
set showcmd  " show command in bottom bar
set lazyredraw  " redraw only when needed. (speeds things up)
set showmatch  " highlight matching braces, brackets, parens

set autowrite
set hidden
set history=30
set scrolloff=8  " scroll down when 8 lines away from being off screen
set sidescrolloff=20 " scroll sideways when 20 columns away from being off screen
set sidescroll=1

" -- SEARCHING
set ignorecase  " ignore case for searches
set incsearch  " search as characters are input
set hlsearch  " highlight search matches
nnoremap <silent> <Esc> :nohlsearch<Bar>:echo<CR>
set magic

" -- INDENT SETTINGS
autocmd Filetype html setlocal ts=2 sw=2 expandtab
autocmd Filetype css setlocal ts=2 sw=2 expandtab
autocmd Filetype ruby setlocal ts=2 sw=2 expandtab
autocmd Filetype javascript setlocal ts=4 sw=4 sts=0 expandtab
autocmd Filetype c setlocal ts=4 sw=4 expandtab cindent
autocmd Filetype swift setlocal ts=4 sw=4 expandtab cindent
autocmd BufNewFile,BufRead *.go setlocal noexpandtab ts=4 sw=4
filetype indent on
filetype plugin indent on
imap <S-tab> <C-d>
set smartindent
set autoindent
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set nowrap

" -- KEY BINDINGS / REMAPS
" gV  - visually selects last inserted block
nnoremap gV `[v`]
" jj  - is escape in insert mode
inoremap jj <esc>
" \j  - next buffer
nnoremap <leader>j :bn<ENTER>
" \jw  - next buffer in new window
nnoremap <leader>wj :sbnext<ENTER>
" \k  - prev buffer
nnoremap <leader>k :bp<ENTER>
" \pp - paste into buffer
nnoremap <leader>pp :r !pbpaste<CR>
" \cc -- copy visually selected text into system clipboard
vmap <leader>cc :'<,'>:w !pbcopy<CR>
" -- GO lang specific remapings
" \rr go run file
autocmd FileType go nmap <leader>rr  <Plug>(go-run)
" \bb go build file
autocmd FileType go nmap <leader>bb :<C-u>call <SID>build_go_files()<CR>
" \tt go test file
autocmd FileType go nmap <leader>tt  <Plug>(go-test)
" \tc go test coverage
autocmd FileType go nmap <Leader>tc <Plug>(go-coverage-toggle)
" \tcb go test coverage show in browser
autocmd FileType go nmap <Leader>tcb <Plug>(go-coverage-browser)
" \gc go run metalinter (ie all of the static analysis tools)
autocmd FileType go nmap <leader>gc :GoMetaLinter<CR>
" \i go show go info for under cursor
autocmd FileType go nmap <Leader>i <Plug>(go-info)
" \e run go rename
au FileType go nmap <Leader>e <Plug>(go-rename)
" ctrl. vim-go quick fix window next error
nnoremap <C-n> :cnext<CR>
" ctrl, vim-go quik fix window prev error
nnoremap <C-m> :cprevious<CR>
" ctrl/ vim-go quick fix window close
nnoremap <leader>c :cclose<CR>

" -- FUNCTIONS
" run :GoBuild or :GoTestCompile based on the go file
function! s:build_go_files()
    let l:file = expand('%')
    if l:file =~# '^\f\+_test\.go$'
        call go#cmd#Test(0, 1)
    elseif l:file =~# '^\f\+\.go$'
        call go#cmd#Build(0)
    endif
endfunction
