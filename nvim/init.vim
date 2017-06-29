" enable python plugins for neovim using neovim's own pyenv
let g:python_host_prog = '/Users/ccummings/.pyenv/versions/neovim2/bin/python'
let g:python3_host_prog = '/Users/ccummings/.pyenv/versions/neovim3/bin/python'


call plug#begin()

    Plug 'w0rp/ale'  " lint engine
    Plug 'janko-m/vim-test'  " test runner engine
    Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
    Plug 'zchee/deoplete-jedi'
    Plug 'tpope/vim-fugitive'
    Plug 'tpope/vim-rhubarb'
    Plug 'tpope/vim-surround'
    Plug 'fatih/vim-go', { 'tag': '*' }
    Plug 'bling/vim-airline'
    Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
    Plug 'mitermayer/vim-prettier', {'do': 'yarn install', 'for': ['javascript', 'typescript', 'css', 'less', 'scss']}

    " syntax color plugins and indent plugins
    Plug 'trevordmiller/nova-vim'
    Plug 'pangloss/vim-javascript'
    Plug 'othree/html5.vim'
    Plug 'hail2u/vim-css3-syntax'
    Plug 'mxw/vim-jsx'

call plug#end()


" / search config
set ignorecase
set smartcase
set magic
set gdefault
nnoremap <silent> <Esc> :nohlsearch<Bar>:echo<CR>

" lint engine configuration options
let g:ale_sign_column_always = 1
let g:ale_fixers = {
    \ 'javascript': ['eslint']
    \ }

" enable deoplete, set tab complettion remap, close scratch window automatically
let g:deoplete#enable_at_startup = 1
inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | pclose | endif

" status line vim airline config
let g:airline#extensions#tabline#enabled = 1

" vim-javascript config
let g:javascript_plugin_flow = 1  " enable javascript flow shit to be highlighted correctly
let g:prettier#exec_cmd_async = 1  " enable async js / css code formatting through prettier
let g:prettier#autoformat = 0
autocmd BufWritePre *.js,*.css,*.scss,*.less PrettierAsync  " runs prettier before saving


" vim-test config
let test#strategy = "neovim"  " runs test in :term instead of :!

" -- Normal Mode Remaps
nnoremap <leader>r :call NumberToggle()<cr>
nnoremap <leader>j :bn<ENTER>
nnoremap <leader>k :bp<ENTER>
nnoremap <leader>T :vsplit term://bash<ENTER>a. ~/.bash_profile<ENTER>
nnoremap <leader>Th :sp term://bash<ENTER>a. ~/.bash_profile<ENTER>
nnoremap <leader>tt :TestFile<ENTER>

" -- Terminal Mode Remaps
:tnoremap <Esc> <C-\><C-n>  " press escape to get into normal mode

" -- Visual Mode Remaps
vmap <leader>cc :'<,'>:w !pbcopy<CR>

" -- misc settings
set number
set relativenumber
set nojoinspaces
set splitright
set scrolloff=3
set sidescrolloff=5
set hidden
colorscheme nova

" -- highlight trailing whitespace and tab characters in red
highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$\|\t/

"###FUNCTIONS###
"###############
function! NumberToggle()
  if(&relativenumber == 1)
    set nornu
    set number
  else
    set rnu
  endif
endfunc
