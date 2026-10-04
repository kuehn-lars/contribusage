#!/usr/bin/env bash
# llm-wiki helper for agents and humans. The protocol lives in AGENTS.md at the repository root.
# How this works, what each lint finding means, and its limits: llm-wiki/guides/llm-wiki-tooling.md
#
#   wiki.sh context                      where we left off: latest handover, git state, recent log, index
#   wiki.sh new-session <slug> [agent]   create this chat's session file, carrying over the latest handover
#   wiki.sh lint                         structural health check; exit 1 if anything is off
#   wiki.sh hook <event>                 Claude Code hooks: session-start | prompt | stop (hook JSON on stdin)
set -uo pipefail

WIKI="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(dirname "$WIKI")"
REL="${WIKI#"$ROOT"/}"
SESSIONS="$WIKI/sessions"
TEMPLATE="$WIKI/_templates/session.md"
REPO_MAP="$WIKI/architecture/repo-map.md"

latest_session() { ls -t "$SESSIONS"/*.md 2>/dev/null | head -1; }

# The "## Handover" section of a session file, heading included.
handover() { awk '/^## Handover/ {p=1; print; next} p && /^## / {exit} p' "$1"; }

# A page without its YAML frontmatter.
body() { awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$1"; }

# Frontmatter value(s) of key $2 in file $1, one per line. Lists may be inline ([a, b]) or block (- a).
fm() {
  awk -v k="$2:" '
    NR==1 && $0!="---" {exit}
    NR>1  && $0=="---" {exit}
    list && /^[ \t]*- / {sub(/^[ \t]*- /, ""); gsub(/["\047]/, ""); print; next}
    {list=0}
    $1==k {
      v=$0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/["\047\[\]]/, "", v)
      if (v=="") {list=1; next}
      n=split(v, a, /,[ \t]*/); for (i=1; i<=n; i++) if (a[i]!="") print a[i]
    }' "$1"
}

# Wikilink targets of a file (code blocks and inline code ignored), as page or page#heading, without |alias.
links() {
  awk '/^[ \t]*(```|~~~)/ {code=!code; next} !code' "$1" | sed 's/`[^`]*`//g' |
    grep -o '\[\[[^]]*\]\]' | sed 's/^\[\[//; s/\]\]$//; s/|.*//' | sort -u
}

# Whether page file $1 has a heading whose text is exactly $2.
has_heading() { awk -v h="$2" 'sub(/^#+[ \t]+/, "") && $0 == h {found = 1; exit} END {exit !found}' "$1"; }

# Wiki pages that lint checks: everything but raw originals, templates, sessions and Obsidian state.
pages() {
  find "$WIKI" -name '*.md' -not -path "$WIKI/raw/*" -not -path "$WIKI/_templates/*" \
       -not -path "$SESSIONS/*" -not -path "$WIKI/.obsidian/*" | sort
}

git_files() { git -C "$ROOT" -c core.quotePath=false ls-files "$@" 2>/dev/null; }

# Files that exist on disk and that git doesn't ignore (tracked or not) under pathspecs $@, repo-relative, sorted.
present_files() {
  comm -23 <(git_files -co --exclude-standard -- "$@" | sort -u) <(git_files -d -- "$@" | sort -u)
}

# The day a repo path last changed (YYYY-MM-DD): its last commit's date, or today if it has uncommitted changes.
changed_on() {
  if [ -n "$(git -C "$ROOT" status --porcelain -- "$1" 2>/dev/null)" ]; then date +%F
  else git -C "$ROOT" log -1 --format=%cs -- "$1" 2>/dev/null; fi
}

cmd_context() {
  local s; s="$(latest_session)"
  echo "# llm-wiki context — $(date '+%F %H:%M')"
  echo
  if [ -n "$s" ]; then
    echo "Latest session: ${s#"$ROOT"/}"
    echo
    handover "$s"
  else
    echo "No session files yet — fresh start."
    echo
  fi
  echo "## Git"
  git -C "$ROOT" status --short --branch 2>/dev/null | head -15
  echo
  echo "## Recent log ($REL/log.md)"
  grep '^## \[' "$WIKI/log.md" | tail -5
  echo
  echo "## Index ($REL/index.md)"
  body "$WIKI/index.md" | awk -v f="$REL/index.md" 'NR <= 200; NR == 201 {print "… truncated: read " f " for the rest"; exit}'
}

cmd_new_session() {
  local slug agent prev prev_ref now file
  slug="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"
  [ -n "$slug" ] || { echo "usage: wiki.sh new-session <topic-slug> [agent]" >&2; return 2; }
  agent="$(printf '%s' "${2:-unknown-agent}" | tr -cd 'A-Za-z0-9._()/ -')"
  prev="$(latest_session)"
  now="$(date '+%F %H:%M')"
  mkdir -p "$SESSIONS"
  file="$SESSIONS/$(printf '%s' "$now" | tr -d ':' | tr ' ' '-')-$slug.md"
  [ -e "$file" ] && { echo "already exists: ${file#"$ROOT"/}" >&2; return 1; }
  prev_ref=""
  [ -n "$prev" ] && prev_ref="[[sessions/$(basename "$prev" .md)]]"
  subst() { sed -e "s|{{date}}|$now|g" -e "s|{{agent}}|$agent|g" -e "s|{{previous}}|\"$prev_ref\"|g"; }
  {
    if [ -n "$prev" ]; then
      # Carry the previous handover over, so the chain never breaks even if this chat dies early.
      sed '/^## Log/,$d; /^- \*\*/d' "$TEMPLATE" | subst
      echo "> Carried over from $prev_ref — not yet updated in this session."
      echo
      handover "$prev" | sed '1d; /^<!--/d; /^> Carried over/d; /^$/d'
      echo
    else
      sed '/^## Log/,$d' "$TEMPLATE" | subst
    fi
    sed -n '/^## Log/,$p' "$TEMPLATE"
  } > "$file"
  echo "${file#"$ROOT"/}"
}

# Per-page checks; each finding is one line starting with the page's name ($2).
# The allowed values mirror the vault table in AGENTS.md; change both together.
check_page() {
  local f="$1" rel="$2" upd type status want link target tracks p
  if [ "$(head -1 "$f")" != "---" ]; then
    echo "$rel: no frontmatter"
  else
    upd="$(fm "$f" updated)"; type="$(fm "$f" type)"; status="$(fm "$f" status)"
    case "$upd" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "$rel: 'updated:' must be a date (YYYY-MM-DD), not '$upd'" ;; esac
    case "$type" in
      index|log) want="" ;;
      decision)  want="proposed accepted superseded" ;;
      research)  want="open answered" ;;
      overview|architecture|module|concept|guide|source) want="planned active stable deprecated" ;;
      *) echo "$rel: unknown type '$type'"; want="$status" ;;
    esac
    case " $want " in *" $status "*) ;; *) echo "$rel: status '$status' is not one of: ${want:-(none)}" ;; esac
  fi
  case "${rel##*/}" in *[!a-z0-9-]*) echo "$rel: file name is not kebab-case" ;; esac
  case "$rel" in
    index|log) ;;
    *) grep -qF -e "[[$rel]]" -e "[[$rel|" "$WIKI/index.md" || echo "$rel: not listed in index.md" ;;
  esac
  links "$f" | while read -r link; do
    target="${link%%#*}"; target="${target:-$rel}"       # [[#heading]] points into this page
    case "$target" in sessions/*) echo "$rel: links into local-only sessions/ ([[$link]])"; continue ;; esac
    if [ -e "$WIKI/$target.md" ]; then
      case "$link" in *'#^'*) ;; *'#'*) has_heading "$WIKI/$target.md" "${link#*#}" || echo "$rel: no heading '${link#*#}' in [[$target]]" ;; esac
    elif [ ! -e "$WIKI/$target" ]; then
      echo "$rel: broken link [[$link]]"
    fi
  done
  # Stale: a tracked path changed on a later day than the page's updated: date, the day it was last checked.
  # ponytail: day precision, so a page checked earlier today misses a later same-day change; the vault holds no times.
  tracks="$(fm "$f" tracks)"
  [ -n "$tracks" ] || return 0
  printf '%s\n' "$tracks" | while read -r p; do
    [ -e "$ROOT/$p" ] || { echo "$rel: tracks a missing path: $p"; continue; }
    [[ "$(changed_on "$p")" > "$upd" ]] &&
      echo "$rel: stale — $p changed after this page's updated: date; update the page (or bump updated: if it still holds)"
  done
}

# Entries directly under $1 ("" = repo root, "llm-wiki/" = vault) vs the repo map's tree at depth $2.
# The tree is the first code block in the repo map; each depth indents by four columns ("│   " or "    ").
check_repo_map() {
  comm -3 <(present_files "${1:-.}" | sed "s|^$1||; s|/.*||" | sort -u) \
          <(awk '/^```/ {n++; next} n == 1' "$REPO_MAP" | grep -oE "^(│   |    ){$2}(├|└)── [^ /]+" | sed 's/.* //' | sort -u) |
    awk -F'\t' -v p="$1" '$1 != "" {print "architecture/repo-map: " p $1 " is missing from the tree"}
                           $2 != "" {print "architecture/repo-map: the tree lists " p $2 ", which does not exist"}'
}

lint_checks() {
  local f rel
  pages | while read -r f; do
    rel="${f#"$WIKI"/}"
    check_page "$f" "${rel%.md}"
  done
  # Page names are unique across folders, so a bare [[name]] typed in Obsidian finds the right page.
  pages | sed 's|.*/||' | sort | uniq -d | sed 's/^/names: /; s/$/ is used in more than one folder/'
  # Decisions are NNNN-slug.md, and parallel branches can hand out the same number twice.
  ls "$WIKI/decisions" 2>/dev/null | grep -v '^[0-9]\{4\}-[a-z0-9-]*\.md$' | sed 's|^|decisions/|; s|$|: name must be NNNN-slug.md|'
  ls "$WIKI/decisions" 2>/dev/null | cut -c1-4 | uniq -d | sed 's|^|decisions: number |; s|$| is used twice|'
  # raw/ keeps originals: files may be added, never changed or removed.
  git -C "$ROOT" -c core.quotePath=false diff --name-only --diff-filter=DMR HEAD -- "$REL/raw" 2>/dev/null |
    sed 's|$|: raw originals are immutable; restore it from git|'
  check_repo_map "" 0
  check_repo_map "$REL/" 1
  # Sessions start with their Handover and stay out of git. One process per check, however many sessions pile up.
  grep -L '^## Handover$' "$SESSIONS"/*.md 2>/dev/null | sed 's|.*/|sessions/|; s|$|: has no ## Handover section|'
  awk 'FNR == 1 {seen = 0} !seen && /^#/ {seen = 1; if ($0 != "## Handover") print FILENAME}' "$SESSIONS"/*.md 2>/dev/null |
    sed 's|.*/|sessions/|; s|$|: first heading must be ## Handover|'
  [ -z "$(git -C "$ROOT" ls-files -- "$REL/sessions/*.md")" ] || echo "sessions/: session files are tracked by git — they must stay local"
  git -C "$ROOT" check-ignore -q "$REL/sessions/probe.md" || echo ".gitignore: $REL/sessions/ is not ignored"
}

cmd_lint() {
  local out; out="$(lint_checks)"
  if [ -z "$out" ]; then echo "wiki lint: clean"; return 0; fi
  printf '%s\n' "$out"
  echo "wiki lint: $(printf '%s\n' "$out" | wc -l | tr -d ' ') issue(s)"
  return 1
}

# The prompt hook's snapshot of the repo: present files outside the wiki.
repo_files() { present_files . ":!$REL"; }

# Files that changed since the prompt hook saved repo_files into marker $1: they appeared or vanished
# (added, moved, deleted) or were written after it. Staging or committing them doesn't hide the change.
turn_changes() {
  local files; files="$(repo_files)"
  { printf '%s\n' "$files" | comm -3 "$1" - | tr -d '\t'
    (cd "$ROOT" && printf '%s\n' "$files" | while read -r f; do [ "$f" -nt "$1" ] && echo "$f"; done)
  } | sort -u | grep .
}

# Stop gate: this turn must have touched a session file, and the wiki too if the repo changed.
stop_check() {
  local marker="$1" missing="" changed
  [ -n "$(find "$SESSIONS" -name '*.md' -newer "$marker" 2>/dev/null)" ] ||
    missing="- your session file in $REL/sessions/: rewrite ## Handover, append a ## Log entry"
  changed="$(turn_changes "$marker")"
  if [ -n "$changed" ] && [ -z "$(find "$WIKI" -name '*.md' -newer "$marker" -not -path "$SESSIONS/*" 2>/dev/null)" ]; then
    missing="${missing:+$missing
}- the wiki: this turn changed $(echo "$changed" | head -3 | tr '\n' ' ')— update the pages that describe it and append to $REL/log.md"
  fi
  [ -z "$missing" ] && return 0
  printf 'llm-wiki protocol — before finishing, update:\n%s\nThen run %s/tools/wiki.sh lint; it names pages whose tracked files changed.\n' "$missing" "$REL" >&2
  return 2
}

cmd_hook() {
  local input sid marker
  input="$(cat)"
  sid="$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -1)"
  marker="${TMPDIR:-/tmp}/llm-wiki-turn-${sid:-unknown}"
  case "${1:-}" in
    session-start)
      cmd_context
      echo
      echo "## llm-wiki protocol"
      if printf '%s' "$input" | grep -Eq '"source" *: *"(resume|compact)"'; then
        echo "Continuing a chat: keep writing to the session file you already own (normally the latest one above) — re-read it now."
      else
        echo "New chat: the Handover above is where we left off. Create your own session file before anything else: $REL/tools/wiki.sh new-session <topic-slug> claude-code"
      fi ;;
    prompt)
      repo_files > "$marker"
      echo "[llm-wiki · $(date '+%F %H:%M')] Orient: read the pages from $REL/index.md this prompt needs. Before your final reply: rewrite ## Handover + append ## Log in your session file; if the repo changed, update affected pages, index.md and log.md, then run $REL/tools/wiki.sh lint." ;;
    stop)
      printf '%s' "$input" | grep -Eq '"stop_hook_active" *: *true' && return 0
      printf '%s' "$input" | grep -Eq '"permission_mode" *: *"plan"' && return 0
      [ -f "$marker" ] || return 0
      stop_check "$marker" ;;
    *) echo "usage: wiki.sh hook session-start|prompt|stop" >&2; return 2 ;;
  esac
}

case "${1:-}" in
  context)     cmd_context ;;
  new-session) shift; cmd_new_session "$@" ;;
  lint)        cmd_lint ;;
  hook)        shift; cmd_hook "$@" ;;
  *)           grep '^#   wiki.sh' "$0" | sed 's/^#   //'; exit 2 ;;
esac
