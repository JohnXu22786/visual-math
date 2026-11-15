#!/usr/bin/env bash
set -euo pipefail

tag_name="${1:?Usage: verify-release-tag.sh <tag-name>}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

tag_ref="repos/${repository}/git/ref/tags/${tag_name}"
tag_object_sha="$(gh api "$tag_ref" --jq 'if .object.type == "tag" then .object.sha else empty end')"
if [[ -z "$tag_object_sha" ]]; then
  echo "::error::Release tag '$tag_name' must be an annotated, signed tag."
  exit 1
fi

tag_data="$(gh api "repos/${repository}/git/tags/${tag_object_sha}" --jq '[.verification.verified, .object.type, .object.sha] | @tsv')"
IFS=$'\t' read -r verification target_type target_commit <<< "$tag_data"
if [[ "$verification" != "true" ]]; then
  echo "::error::Release tag '$tag_name' does not have a verified signature."
  exit 1
fi
if [[ "$target_type" != "commit" || -z "$target_commit" ]]; then
  echo "::error::Release tag '$tag_name' does not point directly to a commit."
  exit 1
fi

checked_out_commit="$(git rev-parse HEAD)"
if [[ "$checked_out_commit" != "$target_commit" ]]; then
  echo "::error::Checked-out source does not match the verified release tag '$tag_name'."
  exit 1
fi

echo "commit=$target_commit" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo "Release tag '$tag_name' has a verified signature."
