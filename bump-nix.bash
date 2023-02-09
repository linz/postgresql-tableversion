#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
shopt -s failglob inherit_errexit

if [[ $# -ne 1 ]]; then
    cat >&2 << EOF
bump-nix.bash: Update nixpkgs.json with latest info from given release

Usage:

./bump-nix.bash RELEASE

Example:

./bump-nix.bash 22.05
    Bumps nixpkgs within the 22.05 release.
EOF
    exit 2
fi

release="$1"

cleanup() {
    rm --force --recursive "$working_dir"
}
trap cleanup EXIT
working_dir="$(mktemp --directory)"

release_file="${working_dir}/release.json"
curl "https://api.github.com/repos/NixOS/nixpkgs/git/refs/heads/release-${release}" > "$release_file"
commit_id="$(jq --raw-output .object.sha "$release_file")"
commit_date="$(curl "https://api.github.com/repos/NixOS/nixpkgs/commits/$commit_id" | jq --raw-output '.commit.committer.date' | tr ':' '-')"

partial_file="${working_dir}/nixpkgs-partial.json"
jq --arg commit_date "$commit_date" --raw-output '{name: (.ref | split("/")[-1] + "-" + $commit_date), url: ("https://github.com/NixOS/nixpkgs/archive/" + .object.sha + ".tar.gz")}' "$release_file" > "$partial_file"

archive_checksum="$(nix-prefetch-url --unpack "$(jq --raw-output .url "$partial_file")")"
full_file="${working_dir}/nixpkgs.json"
jq '. + {sha256: $hash}' --arg hash "$archive_checksum" "$partial_file" > "$full_file"

target_file='./nixpkgs.json'
if diff "$target_file" "$full_file"; then
    echo "No change; aborting." >&2
else
    mv "$full_file" "$target_file"
fi
