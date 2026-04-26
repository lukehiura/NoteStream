#!/usr/bin/env bash
# Apply GitHub repo settings, labels, and (optionally) branch/tag protection via GitHub CLI.
# Requires: gh auth login, permission to edit the repository.
# Safe to re-run (labels use || true).
#
# Solo maintainer: GitHub still counts you as one approver for required reviews in many setups,
# but if merges block, set GH_REQUIRED_REVIEW_COUNT=0 when applying branch protection.
#
# Usage (from repo root):
#   ./scripts/gh-repo-harden.sh
#   APPLY_BRANCH_PROTECTION=1 ./scripts/gh-repo-harden.sh   # after CI has reported check "Swift checks"
#   APPLY_TAG_RULESET=1 ./scripts/gh-repo-harden.sh         # if rulesets are enabled for your org/account
set -euo pipefail

OWNER="${OWNER:-lukehiura}"
REPO="${REPO:-NoteStream}"
FULL="$OWNER/$REPO"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
REVIEW_COUNT="${GH_REQUIRED_REVIEW_COUNT:-1}"
APPLY_BRANCH_PROTECTION="${APPLY_BRANCH_PROTECTION:-0}"
APPLY_TAG_RULESET="${APPLY_TAG_RULESET:-0}"

echo "Using repository: $FULL (default branch: $DEFAULT_BRANCH)"
gh repo set-default "$FULL"

echo "Updating repository merge and feature flags..."
gh repo edit "$FULL" \
  --enable-issues=true \
  --enable-projects=false \
  --enable-wiki=false \
  --enable-discussions=true \
  --enable-squash-merge=true \
  --enable-merge-commit=false \
  --enable-rebase-merge=false \
  --delete-branch-on-merge=true \
  --enable-auto-merge=true

echo "Setting repository topics (replaces existing topic list)..."
gh api --method PUT "/repos/$FULL/topics" --input - <<'TOPICS'
{"names":["macos","swift","transcription","whisperkit","ollama","ai-notes"]}
TOPICS

echo "Setting default Actions workflow token to read-only..."
gh api \
  --method PUT \
  "/repos/$FULL/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false

echo "Creating labels (ignore errors if they already exist)..."
gh label create "dependencies" --color "0366d6" --description "Dependency updates" || true
gh label create "swift" --color "F05138" --description "Swift package dependencies" || true
gh label create "github-actions" --color "2088FF" --description "GitHub Actions workflow updates" || true
gh label create "type: bug" --color "d73a4a" --description "Something is broken" || true
gh label create "type: feature" --color "a2eeef" --description "New feature or enhancement" || true
gh label create "type: docs" --color "0075ca" --description "Documentation change" || true
gh label create "type: release" --color "5319e7" --description "Release and packaging work" || true
gh label create "area: transcription" --color "1d76db" --description "Transcription pipeline" || true
gh label create "area: ai-notes" --color "7057ff" --description "AI notes and summarization" || true
gh label create "area: speaker-diarization" --color "fbca04" --description "Speaker labeling and diarization" || true
gh label create "area: macos" --color "0e8a16" --description "macOS app behavior" || true
gh label create "security" --color "ee0701" --description "Security-sensitive issue" || true
gh label create "good first issue" --color "7057ff" --description "Good for first-time contributors" || true

if [[ "$APPLY_BRANCH_PROTECTION" == "1" ]]; then
  echo "Applying branch protection to $DEFAULT_BRANCH (required check: Swift checks, reviews: $REVIEW_COUNT)..."
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  cat >"$tmp" <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Swift checks"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": $REVIEW_COUNT,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
  gh api \
    --method PUT \
    "/repos/$FULL/branches/$DEFAULT_BRANCH/protection" \
    -H "Accept: application/vnd.github+json" \
    --input "$tmp"
  echo "Branch protection applied."
else
  echo "Skipping branch protection (set APPLY_BRANCH_PROTECTION=1 after a green CI run exposes check \"Swift checks\")."
fi

if [[ "$APPLY_TAG_RULESET" == "1" ]]; then
  ruleset_file=".github/rulesets/release-tags.json"
  if [[ ! -f "$ruleset_file" ]]; then
    echo "Missing $ruleset_file" >&2
    exit 1
  fi
  echo "Creating tag ruleset from $ruleset_file ..."
  gh api \
    --method POST \
    "/repos/$FULL/rulesets" \
    --input "$ruleset_file" || {
    echo "Tag ruleset creation failed (org/plan may not support rulesets). Keep a manual convention: do not delete or force-move v* tags." >&2
    exit 1
  }
  echo "Tag ruleset applied."
else
  echo "Skipping tag ruleset (set APPLY_TAG_RULESET=1 to POST .github/rulesets/release-tags.json)."
fi

echo "Done. Inspect protection: gh api \"/repos/$FULL/branches/$DEFAULT_BRANCH/protection\" --jq ."
