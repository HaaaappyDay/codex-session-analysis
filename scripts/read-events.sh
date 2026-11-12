#!/usr/bin/env bash
# Read-only, bounded JSONL view. Requires jq 1.6+ and sed.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 3 ]]; then
  printf '%s\n' 'Usage: bash read-events.sh FILE [START_LINE=1] [COUNT=20]' >&2
  exit 2
fi
for dependency in sed jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Missing dependency: %s\n' "$dependency" >&2
    exit 127
  fi
done
session_file=$1
first_line=${2:-1}
line_count=${3:-20}
if [[ ! -f "$session_file" || ! -r "$session_file" ]]; then
  printf '%s\n' 'FILE must be a readable regular file.' >&2
  exit 2
fi
if [[ ! "$first_line" =~ ^[1-9][0-9]{0,8}$ || ! "$line_count" =~ ^[1-9][0-9]?$ ]]; then
  printf '%s\n' 'START_LINE must be 1..999999999; COUNT must be 1..50.' >&2
  exit 2
fi
if (( line_count > 50 )); then
  printf '%s\n' 'COUNT must be at most 50.' >&2
  exit 2
fi
# Absolute paths avoid interpreting a leading hyphen as a sed option.
case "$session_file" in
  /*) ;;
  *) session_file="$PWD/$session_file" ;;
esac
last_line=$((first_line + line_count - 1))
sed -n "${first_line},${last_line}p;${last_line}q" "$session_file" |
  jq -Rc --argjson first "$first_line" '
    (input_line_number + $first - 1) as $line
    | try (
        fromjson
        | walk(
            if type == "object" and has("encrypted_content") then
              .encrypted_content = "[encrypted content omitted]"
            else . end
          )
        | walk(
            if type == "object" then
              if (.type == "image" or .type == "audio") and (.data | type) == "string" then
                .data = "[binary media omitted]"
              elif has("mimeType") and (.blob | type) == "string" then
                .blob = "[resource blob omitted]"
              else . end
            else . end
          )
        | walk(
            if type == "string" then
              if startswith("data:") then "[data URI omitted]"
              elif length > 2000 then .[0:2000] + " [truncated; reread this field]"
              else . end
            else . end
          )
        | {line: $line, event: .}
      ) catch {line: $line, parse_error: "Invalid JSON or unsupported value; inspect this physical line separately"}
  '
