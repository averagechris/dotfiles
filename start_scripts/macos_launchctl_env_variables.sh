#!/bin/sh
launchctl setenv WORKON_HOME "$HOME/.local/share/virtualenvs/"
launchctl setenv PATH "$PATH:/usr/local/bin:$HOME/dotfiles/bin:$HOME/.cargo/bin:$HOME/.pyenv/:$HOME/.pyenv/versions:$HOME/.pyenv/shims"
launchctl setenv RUST_SRC_PATH "$HOME/.rustup/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src"

# this is used in launchctl env variables start script
