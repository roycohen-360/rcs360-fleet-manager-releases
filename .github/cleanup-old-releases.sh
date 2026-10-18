#!/usr/bin/env bash
# Deletes every published release older than KEEP_DAYS (default 7), together
# with its tag — EXCEPT the one GitHub marks "Latest".
#
# The Latest release is the update feed: installed copies read its latest.yml,
# and https://github.com/roycohen-360/rcs360-fleet-manager-releases/releases/latest
# is the link new clients get. Deleting it breaks both, however old it is.
#
# Drafts are never touched — a draft is a release being prepared.
#
# Cost of deleting: a client still on a deleted version downloads the full
# installer instead of only the difference (electron-updater fetches the old
# version's .blockmap from its release, falls back to a full download when it
# is gone). Nothing breaks.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
keep_days="${KEEP_DAYS:-7}"

# Without knowing which release is Latest, every release looks deletable.
# A failed lookup (no releases yet, an API error) deletes nothing.
latest="$(gh api "repos/$repo/releases/latest" --jq .tag_name)" || latest=""
if [ -z "$latest" ]; then
  echo "No Latest release found — deleting nothing."
  exit 0
fi

cutoff="$(date -u -d "$keep_days days ago" +%s)"
echo "Keeping $latest, drafts, and anything published in the last $keep_days days."

gh api --paginate "repos/$repo/releases" \
  --jq '.[] | "\(.tag_name)\t\(.draft)\t\(.published_at)"' |
while IFS=$'\t' read -r tag draft published; do
  if [ "$draft" = "true" ] || [ "$tag" = "$latest" ]; then continue; fi
  if [ "$(date -u -d "$published" +%s)" -ge "$cutoff" ]; then continue; fi
  echo "Deleting $tag (published $published)"
  # </dev/null: `gh` must not read the rest of this loop's input.
  gh release delete "$tag" --repo "$repo" --yes --cleanup-tag </dev/null
done
