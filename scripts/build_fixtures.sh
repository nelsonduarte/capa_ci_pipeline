#!/usr/bin/env sh
# Build every action .wasm Component Model fixture from its .wat core
# module and .wit world, exactly the way the compiler's own
# tests/fixtures/foreign/*.wasm were built:
#
#   wasm-tools parse   <core>.wat            -> <core>.wasm   (core module)
#   wasm-tools component embed --world <w> <wit> <core>.wasm  (embed types)
#   wasm-tools component new   <embedded>    -> <name>.wasm   (component)
#
# Requires wasm-tools on PATH. Run from anywhere; paths are resolved
# relative to this script. The built .wasm land next to their sources in
# actions/, and are then copied to the locations the demo runs from (the
# product root and each negative directory).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/actions/src"
out="$root/actions"

build() {
  name=$1
  world=$2
  echo "building $name.wasm (world $world)"
  wasm-tools parse "$src/$name.wat" -o "$out/$name.core.wasm"
  wasm-tools component embed --world "$world" "$src/$name.wit" \
    "$out/$name.core.wasm" -o "$out/$name.embed.wasm"
  wasm-tools component new "$out/$name.embed.wasm" -o "$out/$name.wasm"
  rm -f "$out/$name.core.wasm" "$out/$name.embed.wasm"
}

build fetch fetch
build parse parse
build build build
build publish publish
build mal_parse malparse

# The product root runs main.capa, which invokes the actions; the
# compiler resolves each extern-component artifact path relative to the
# root source file, so the four honest action components must sit here.
cp "$out/fetch.wasm"   "$root/fetch.wasm"
cp "$out/parse.wasm"   "$root/parse.wasm"
cp "$out/build.wasm"   "$root/build.wasm"
cp "$out/publish.wasm" "$root/publish.wasm"

# The compromised-parser negative runs from its own directory.
cp "$out/mal_parse.wasm" "$root/negatives/ungranted_cap/mal_parse.wasm"

echo "done"
