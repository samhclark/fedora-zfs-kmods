#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE >&2
Usage: $0 --retention-days <days> --min-versions <count> --dry-run <true|false> [--github-output <path>]

Examples:
  $0 --retention-days 90 --min-versions 3 --dry-run true
  $0 --retention-days 60 --min-versions 5 --dry-run false --github-output "$GITHUB_OUTPUT"
USAGE
}

retention_days=""
min_versions=""
dry_run="true"
github_output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retention-days)
      retention_days=$2
      shift 2
      ;;
    --min-versions)
      min_versions=$2
      shift 2
      ;;
    --dry-run)
      dry_run=$2
      shift 2
      ;;
    --github-output)
      github_output=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$retention_days" || -z "$min_versions" ]]; then
  usage
  exit 1
fi

if [[ -z "$dry_run" ]]; then
  dry_run="true"
fi

if ! [[ $retention_days =~ ^[0-9]+$ ]]; then
  echo "retention-days must be an integer" >&2
  exit 1
fi

if ! [[ $min_versions =~ ^[0-9]+$ ]]; then
  echo "min-versions must be an integer" >&2
  exit 1
fi

if [[ "$dry_run" != "true" && "$dry_run" != "false" ]]; then
  echo "dry-run must be either true or false" >&2
  exit 1
fi

printf '🧪 Testing cleanup logic'
if [[ "$dry_run" == "true" ]]; then
  printf ' (DRY RUN)'
fi
printf '\n'

echo "📅 Retention period: ${retention_days} days"
echo "🔒 Minimum versions to keep: ${min_versions}"
echo ""

cutoff_date=$(date -d "${retention_days} days ago" -u +"%Y-%m-%dT%H:%M:%SZ")
echo "📅 Cutoff date: $cutoff_date"
echo ""

echo "🔍 Querying all package versions..."
versions_json=$(gh api "/user/packages/container/fedora-zfs-kmods/versions" --paginate)

total_versions=$(printf '%s' "$versions_json" | jq length)
echo "📦 Total versions found: $total_versions"
echo ""

all_versioned_tags_json=$(printf '%s' "$versions_json" | jq -c '
  [
    .[] as $item |
    ($item.metadata.container.tags // []) as $tags |
    $tags[]? |
    select(test("^zfs-.*_kernel-.*$")) |
    {created_at: $item.created_at, tag: ., id: $item.id}
  ] | sort_by(.created_at) | reverse
')

total_versioned_count=$(printf '%s' "$all_versioned_tags_json" | jq length)
echo "🏷️  Total versioned tags found: $total_versioned_count"

echo ""

if (( total_versioned_count < min_versions )); then
  echo "❌ EARLY SAFETY CHECK FAILED: Only $total_versioned_count versioned tags exist in repository (minimum ${min_versions} required)" >&2
  echo "📋 Available versioned tags:" >&2
  printf '%s' "$all_versioned_tags_json" | jq -r '.[].tag' >&2
  echo "" >&2
  echo "🚨 Cannot proceed with cleanup - insufficient versioned tags to maintain minimum policy" >&2
  echo "This indicates the repository needs more tagged releases before cleanup can run safely" >&2
  exit 1
fi

mapfile -t protected_versioned_tags < <(printf '%s' "$all_versioned_tags_json" | jq -r ".[0:${min_versions}] | .[].tag")

echo "🛡️  Protected tags (${min_versions} most recent):"
if ((${#protected_versioned_tags[@]} > 0)); then
  printf '%s\n' "${protected_versioned_tags[@]}"
fi
echo ""

declare -a protected_digests=()
for tag in "${protected_versioned_tags[@]}"; do
  if [[ -n "$tag" ]]; then
    digest=$(printf '%s' "$versions_json" | jq -r --arg tag "$tag" '.[] | select(.metadata.container.tags[]? == $tag) | .name' | head -n1)
    if [[ -n "$digest" && "$digest" != "null" ]]; then
      attestation_tag="sha256-${digest#sha256:}"
      protected_digests+=("$attestation_tag")
      echo "🔐 $tag -> $attestation_tag"
    fi
  fi
done
echo ""

protected_all=()
protected_all+=("${protected_versioned_tags[@]}")
protected_all+=("${protected_digests[@]}")

if ((${#protected_all[@]} > 0)); then
  protected_all_json=$(printf '%s\n' "${protected_all[@]}" | jq -R . | jq -s .)
else
  protected_all_json='[]'
fi

candidates_json=$(printf '%s' "$versions_json" | jq --arg cutoff "$cutoff_date" --argjson protected "$protected_all_json" '
  [
    .[] as $item |
    ($item.metadata.container.tags // []) as $tags |
    ($tags | length) as $tag_count |
    (if $tag_count > 0 then $tags else ["<untagged>"] end) as $safe_tags |
    select(
      ($item.created_at < $cutoff) and
      (reduce $safe_tags[] as $tag (true; . and (($protected | index($tag)) == null)))
    ) |
    {
      id: $item.id,
      created_at: $item.created_at,
      tags: $safe_tags
    }
  ]
')

candidate_count=$(printf '%s' "$candidates_json" | jq length)

delete_ids=$(printf '%s' "$candidates_json" | jq -r 'map(.id | tostring) | join(",")')

if [[ -n "$github_output" ]]; then
  echo "delete_versions=${delete_ids}" >> "$github_output"
fi

echo "🔍 Safety validation:"
echo "  - Total versioned tags in repository: $total_versioned_count"
echo "  - Versioned tags being protected: ${min_versions}"
echo "  - Protected attestations: ${#protected_digests[@]}"

echo ""

echo "🗑️  Identifying deletion candidates..."
if (( candidate_count > 0 )); then
  printf '%s' "$candidates_json" | jq -r '.[] | "\(.tags | join(", ")) - \(.created_at) - ID: \(.id)"' | sort
  echo ""
  echo "📊 Summary:"
  echo "  - Deletion candidates: $candidate_count"
  echo "  - Total versions: $total_versions"
  echo "  - Protected versions: ${min_versions}"
  echo "  - Protected attestations: ${#protected_digests[@]}"
  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "🧪 DRY RUN - No versions were deleted"
  else
    echo ""
    echo "🗑️  Proceed with deletion by removing dry-run protection"
  fi
else
  echo "  No versions would be deleted"
  echo ""
  echo "📊 Summary:"
  echo "  - Deletion candidates: 0"
  echo "  - Total versions: $total_versions"
  echo "  - Protected versions: ${min_versions}"
  echo "  - Protected attestations: ${#protected_digests[@]}"
fi

if [[ "$dry_run" == "true" ]]; then
  echo ""
  echo "🔒 Safety mechanisms active:"
  echo "  - Minimum ${min_versions} versioned tags protected"
  echo "  - Attestations preserved for retained images"
  echo "  - ${retention_days}-day retention window enforced"
fi
