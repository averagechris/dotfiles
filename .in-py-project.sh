#!/usr/bin/env sh

_cwd=$(pwd)
_pyroot=$(find . -name pyproject.toml | sed 's/\/pyproject.toml//')

cd "$_pyroot" || exit
eval "$@"
cd "$_cwd" || exit
