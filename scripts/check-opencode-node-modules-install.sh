#!/usr/bin/env bash
set -euo pipefail

for tool in find cp diff stat readlink; do
  if ! "$tool" --version >/dev/null 2>&1; then
    printf 'GNU %s is required\n' "$tool" >&2
    exit 2
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src="$work/src"
old="$work/old"
new="$work/new"
mkdir -p "$src/packages/app/node_modules/outer/node_modules/inner/bin" "$old" "$new"
printf '{"name":"fixture"}\n' >"$src/package.json"
printf '{"name":"app"}\n' >"$src/packages/app/package.json"
printf '#!/bin/sh\nexit 0\n' >"$src/packages/app/node_modules/outer/node_modules/inner/bin/tool"
chmod 755 "$src/packages/app/node_modules/outer/node_modules/inner/bin/tool"
ln -s bin/tool "$src/packages/app/node_modules/outer/node_modules/inner/tool-link"
ln -s inner "$src/packages/app/node_modules/outer/node_modules/inner-link"

(
  cd "$src"
  find . -type d -name node_modules -exec cp -R --parents {} "$old" \;
)

cp -R "$src"/. "$new"
test -f "$new/package.json"
test -f "$new/packages/app/package.json"

find "$new" -depth -mindepth 1 \
  ! -path '*/node_modules' \
  ! -path '*/node_modules/*' \
  \( ! -type d -o -empty \) \
  -delete

diff -r --no-dereference "$old" "$new"
test "$(stat -c '%a' "$new/packages/app/node_modules/outer/node_modules/inner/bin/tool")" = 755
test "$(readlink "$new/packages/app/node_modules/outer/node_modules/inner/tool-link")" = bin/tool
test "$(readlink "$new/packages/app/node_modules/outer/node_modules/inner-link")" = inner
test ! -e "$new/package.json"
test ! -e "$new/packages/app/package.json"
printf 'copied and pruned output is equivalent to the old node_modules install\n'
