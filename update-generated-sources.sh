#!/usr/bin/env bash

set -o pipefail
set -e

MANIFEST_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
TOOLS_DIR="${TOOLS_DIR:-"$MANIFEST_DIR/tools"}"

GENERATED_SOURCES="generated-sources.json"
MANIFEST_PATH="$MANIFEST_DIR/net.veloren.veloren.yaml"
MODULE_NAME=${MODULE_NAME:-"veloren"}

MODULE_OBJ=$(
    python3 -c 'import sys,json,yaml; json.dump(yaml.safe_load(sys.stdin), sys.stdout)' \
    < "$MANIFEST_PATH" | \
    jq -e \
        --arg MODULE_NAME "$MODULE_NAME" \
        '.modules | map(select(objects | .name==$MODULE_NAME)) | first'
)
SOURCE_OBJ=$(
    jq -e '.sources | map(select(objects | .type=="git")) | first' \
    <<<"$MODULE_OBJ"
)

SOURCE_URL="$(jq -r '.url' <<<"$SOURCE_OBJ")"
SOURCE_TAG="$(jq -r '.tag' <<<"$SOURCE_OBJ")"

CLONE_DIR="$(mktemp -d "${TMPDIR:-"/tmp"}/$MODULE_NAME.XXXXXX")"

GIT_LFS_SKIP_SMUDGE=1 git clone --depth=1 --branch="$SOURCE_TAG" "$SOURCE_URL" "$CLONE_DIR"

while read -r patch_path; do
    echo "Applying patch $patch_path" >> /dev/stderr
    patch -d "$CLONE_DIR" -p1 < "$MANIFEST_DIR/$patch_path"
done < <(
    jq -r -e '.sources[] | objects | select(.type=="patch") | .path // .paths[]' \
    <<<"$MODULE_OBJ"
)

TOOLS_VENV="$TOOLS_DIR/cargo/.venv"

if ! test -d "$TOOLS_VENV"; then
    python3 -m venv "$TOOLS_VENV"
fi

if ! "$TOOLS_VENV/bin/python3" -c 'pass'; then
    echo 'It seems that your venv is broken!' >&2
    echo Try deleting the following directory: "$TOOLS_VENV" >&2
    exit 1
fi

"$TOOLS_VENV/bin/pip3" install "$TOOLS_DIR/cargo/"

"$TOOLS_VENV/bin/python3" "$TOOLS_DIR/cargo/flatpak-cargo-generator.py" \
    --output "$MANIFEST_DIR/$GENERATED_SOURCES" \
    "$CLONE_DIR/Cargo.lock"

if ! git -C "$MANIFEST_DIR" diff --exit-code -- "$GENERATED_SOURCES" >> /dev/null; then
    git -C "$MANIFEST_DIR" add "$GENERATED_SOURCES"
    git -C "$MANIFEST_DIR" commit -m "Update $GENERATED_SOURCES for $MODULE_NAME $SOURCE_TAG"
fi
