" --- the plugins are between the call plug begin and end
call plug#begin('~/.vim/plugged')
Plug 'tpope/vim-surround'
call plug#end()

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
" \pp - paste into buffer
nnoremap <leader>pp :r !pbpaste<CR>
" \cc -- copy visually selected text into system clipboard
vmap <leader>cc :'<,'>:w !pbcopy<CR>
