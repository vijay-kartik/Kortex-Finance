#!/usr/bin/env bash
# Turns the execution file that anthropics/claude-code-action writes (every SDK message of the
# session) into a readable report. The action itself only logs "full output hidden for security",
# so without this a failed run says nothing about what Claude did.
#
#   claude-run-report.sh <execution-file> [<notes-out>]
#
# Prints the report to the job log, appends it to the run's summary page ($GITHUB_STEP_SUMMARY),
# and, given <notes-out>, writes a short Markdown excerpt (outcome, denied tool calls, Claude's
# last message) for a workflow to post on the issue.
#
# Tool output is only shown for failed calls, and clipped: the log masks secrets, and the
# repository is public.
set -euo pipefail

file=${1:-}
notes=${2:-}

if [ -z "$file" ] || [ ! -s "$file" ]; then
  echo "No Claude execution file at '${file}'; Claude probably did not start."
  [ -n "$notes" ] && echo "Claude did not start (no execution output); check the earlier steps of the run." > "$notes"
  exit 0
fi

# The file is a JSON array of messages; read JSON Lines too, in case the format changes.
lib='
def msgs: [ .[] | if type == "array" then .[] else . end ];
def clip($n): if length > $n then .[:$n] + " … (\(length - $n) more chars)" else . end;
def oneline: gsub("\\s*\n\\s*"; " ⏎ ");
def text_of: if type == "string" then . elif type == "array" then [ .[] | .text? // empty ] | join("\n") else tostring end;
def describe:
  .name as $n | (.input // {}) as $i
  | "\($n): " + (
      if $n == "Bash" then ($i.command // "")
      elif $i.file_path? then $i.file_path
      elif $i.pattern? then $i.pattern + (if $i.path? then " in \($i.path)" else "" end)
      else ($i | tojson) end
    | oneline | clip(400));

msgs as $m
| ($m | map(select(.type == "result")) | last // {}) as $r
| [ $r.permission_denials[]?.tool_use_id ] as $denied
| ([ $m[] | select(.type == "user") | .message.content | arrays | .[]
     | select(.type == "tool_result")
     | { key: .tool_use_id, value: { err: (.is_error == true), text: (.content | text_of) } } ]
   | from_entries) as $results
| [ $m[] | select(.type == "assistant") | .message.content[]? | select(.type == "text" or .type == "tool_use") ] as $blocks
|
'

summary=$(jq -rs "$lib"'
  "Outcome: \($r.subtype // "unknown (no result message)")\(if $r.is_error then " (error)" else "" end)"
  + " · turns: \($r.num_turns // "?")"
  + " · tool calls: \([ $blocks[] | select(.type == "tool_use") ] | length)"
  + " · permission denials: \($denied | length)"
  + " · duration: \(($r.duration_ms // 0) / 60000 * 10 | round / 10) min"
  + " · cost: $\($r.total_cost_usd // 0 | . * 100 | round / 100)"
' "$file")

denials=$(jq -rs "$lib"'
  $r.permission_denials[]? | "\(.tool_name): " + (
    if .tool_name == "Bash" then (.tool_input.command // "")
    elif .tool_input.file_path? then .tool_input.file_path
    else (.tool_input | tojson) end
    | oneline | clip(400))
' "$file")

final=$(jq -rs "$lib"'
  ($r.result // ([ $blocks[] | select(.type == "text") ] | last | .text?) // "") | clip(4000)
' "$file")

transcript=$(jq -rs "$lib"'
  foreach $blocks[] as $b (0; if $b.type == "tool_use" then . + 1 else . end;
    if $b.type == "text" then
      "  Claude: " + ($b.text | clip(800) | gsub("\n"; "\n          "))
    else
      $results[$b.id] as $res
      | "#\(.) " + ($b | describe)
        + (if ($denied | any(. == $b.id)) then "\n     ✗ DENIED: not allowed by --allowedTools"
           elif $res.err then "\n     ✗ error: " + ($res.text | oneline | clip(600))
           elif $res == null then "\n     (no result; the session ended here)"
           else "" end)
    end)
' "$file")

{
  echo "=== Claude run report ==="
  echo "$summary"
  echo
  if [ -n "$denials" ]; then
    echo "--- Permission denials (commands Claude tried that --allowedTools blocks) ---"
    echo "$denials"
    echo
  fi
  echo "--- Claude's last message ---"
  echo "${final:-(none)}"
  echo
  echo "--- Transcript (tool calls in order; failed calls show their error) ---"
  echo "${transcript:-(no tool calls)}"
}

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Claude run report"
    echo
    echo "$summary"
    echo
    if [ -n "$denials" ]; then
      echo "### Permission denials"
      echo
      echo "Commands Claude tried that \`--allowedTools\` blocks:"
      echo
      echo '````text'
      echo "$denials"
      echo '````'
      echo
    fi
    echo "### Claude's last message"
    echo
    echo "${final:-_(none)_}"
    echo
    echo "<details><summary>Transcript</summary>"
    echo
    echo '````text'
    echo "${transcript:-(no tool calls)}"
    echo '````'
    echo
    echo "</details>"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ -n "$notes" ]; then
  {
    echo "$summary"
    if [ -n "$denials" ]; then
      echo
      echo "**Blocked tool calls** (not in \`--allowedTools\`):"
      echo '````text'
      echo "$denials"
      echo '````'
    fi
    echo
    echo "**Claude's last message:**"
    echo
    if [ -n "$final" ]; then printf '%s\n' "$final" | sed 's/^/> /'; else echo "> (none)"; fi
  } > "$notes"
fi
