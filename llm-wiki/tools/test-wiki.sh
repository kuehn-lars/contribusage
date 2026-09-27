#!/usr/bin/env bash
# Regression test for wiki.sh: lint, the Stop gate and new-session, run against a throwaway copy of this repo.
# Run it after changing wiki.sh:  llm-wiki/tools/test-wiki.sh   (exit 1 on any failure; touches only a temp dir)
set -uo pipefail

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"                                   # the hooks keep their per-turn marker here
cp -R "$(cd "$(dirname "$0")/../.." && pwd)" "$TMP/repo" && cd "$TMP/repo" || exit 1
W=llm-wiki/tools/wiki.sh
G() { git -c user.name=test -c user.email=test@example.com "$@"; }
G add -A && G commit -qm baseline --allow-empty && BASE="$(git rev-parse HEAD)"
reset() { git reset -q --hard "$BASE" && git clean -qfd; }  # gitignored sessions survive
passed=0 failed=0
ok()   { echo "ok    $1"; passed=$((passed + 1)); }
fail() { echo "FAIL  $1"; failed=$((failed + 1)); }

# page <rel> [frontmatter lines] [body]: a concept page listed in the index; given keys replace the defaults.
page() {
  local fm="${2:-}"
  case "$fm" in *type:*) ;; *) fm="type: concept\n$fm" ;; esac
  case "$fm" in *status:*) ;; *) fm="status: active\n$fm" ;; esac
  case "$fm" in *updated:*) ;; *) fm="updated: 2026-01-01\n$fm" ;; esac
  mkdir -p "llm-wiki/$(dirname "$1")"
  printf -- '---\n%b---\n# Test\n%b\n' "$fm" "${3:-}" > "llm-wiki/$1.md"
  echo "- [[$1]]" >> llm-wiki/index.md
}
lint_has()   { local out; out="$($W lint)"; case "$out" in *"$2"*) ok "$1" ;; *) fail "$1 — lint said: $out" ;; esac; reset; }
lint_lacks() { local out; out="$($W lint)"; case "$out" in *"$2"*) fail "$1 — lint said: $out" ;; *) ok "$1" ;; esac; reset; }
lint_clean() { local out; out="$($W lint)"; [ "$out" = "wiki lint: clean" ] && ok "$1" || fail "$1 — lint said: $out"; reset; }

# gate <description> <expected stop-hook exit> <commands run during the turn>. MODE/EXTRA tweak the hook JSON.
hook() { printf '{"session_id":"test","permission_mode":"%s"%s}' "${MODE:-default}" "${EXTRA:-}" | $W hook "$1"; }
gate() {
  hook prompt >/dev/null; sleep 1                      # bash 3.2 compares mtimes in whole seconds
  eval "$3"
  hook stop 2>/dev/null; local rc=$?
  [ "$rc" = "$2" ] && ok "$1" || fail "$1 — stop hook exit $rc, want $2"
  reset
}

echo "## new-session and context"
first="$($W new-session first tester)" && sed -i.bak 's/^- \*\*Goal:\*\*.*/- **Goal:** carry-me-over/' "$first" && rm "$first.bak"
sleep 1
S="$($W new-session second tester)"
grep -q '^- \*\*Goal:\*\* carry-me-over' "$S" && ok "new-session carries the previous handover over" || fail "handover not carried over"
grep -q "^previous: \"\[\[sessions/$(basename "$first" .md)\]\]\"" "$S" && ok "new-session links the previous session" || fail "previous: link missing"
[ "$(grep -c '^## ' "$S")" = 2 ] && ok "new-session writes exactly Handover + Log" || fail "unexpected sections in $S"
case "$($W context)" in *"Latest session: $S"*) ok "context shows the newest session" ;; *) fail "context shows the wrong session" ;; esac

echo "## lint"
lint_clean "baseline is clean"
page guides/x;                                    lint_clean "a valid new page is clean"
printf '# X\n' > llm-wiki/guides/x.md;            lint_has "missing frontmatter" "guides/x: no frontmatter"
page guides/x; sed -i.bak '$d' llm-wiki/index.md; rm llm-wiki/index.md.bak
                                                    lint_has "page missing from the index" "guides/x: not listed in index.md"
page guides/x '' '[[nope/nothing]]';              lint_has "broken link" "broken link [[nope/nothing]]"
page guides/x '' '```\n[[nope/nothing]]\n```';    lint_clean "links inside code blocks are ignored"
page guides/x '' '[[overview#System at a glance]] [[overview#System at a glance|the targets]]'; lint_clean "valid heading links"
page guides/x '' '[[overview#No such heading]]';   lint_has "link to a missing heading" "guides/x: no heading 'No such heading' in [[overview]]"
page guides/x 'type: research\nstatus: open\n';   lint_clean "research page with its own statuses"
page guides/x 'type: research\n';                 lint_has "research page with a lifecycle status" "status 'active' is not one of: open answered"
page guides/x '' '[[sessions/whatever]]';         lint_has "link into sessions/" "links into local-only sessions/"
page guides/x 'updated: someday\n';               lint_has "bad updated:" "'updated:' must be a date"
page guides/x 'type: essay\n';                    lint_has "unknown type" "unknown type"
page guides/x 'status: done\n';                   lint_has "bad status" "status 'done' is not one of"
page guides/Bad_Name;                             lint_has "non-kebab-case name" "guides/Bad_Name: file name is not kebab-case"
page guides/overview;                             lint_has "duplicate page name" "names: overview.md is used in more than one folder"
cp llm-wiki/decisions/0001-*.md llm-wiki/decisions/0001-other.md; echo '- [[decisions/0001-other]]' >> llm-wiki/index.md
                                                    lint_has "duplicate decision number" "decisions: number 0001 is used twice"
printf -- '---\ntype: decision\nstatus: proposed\nupdated: 2026-01-01\n---\n' > llm-wiki/decisions/idea.md; echo '- [[decisions/idea]]' >> llm-wiki/index.md
                                                    lint_has "decision without a number" "decisions/idea.md: name must be NNNN-slug.md"
mkdir -p llm-wiki/raw && echo x > llm-wiki/raw/a.md && G add -A && G commit -qm raw && echo y >> llm-wiki/raw/a.md
                                                    lint_has "edited raw original" "raw originals are immutable"
mkdir -p llm-wiki/raw && echo x > llm-wiki/raw/a.md; lint_lacks "adding a raw original is fine" "immutable"
page guides/x 'tracks: [nope.txt]\n';             lint_has "tracked path missing" "tracks a missing path: nope.txt"
page guides/x 'tracks: [README.md]\n'; G add -A; G commit -qm page; echo x >> README.md
                                                    lint_has "code changed after its page" "guides/x: stale — README.md changed after this page"
page guides/x 'tracks: [README.md]\n'; G add -A; G commit -qm page; echo x >> README.md; echo x >> llm-wiki/guides/x.md
                                                    lint_clean "page updated along with its code"
page guides/x 'tracks:\n  - README.md\n  - "llm-wiki/tools/a b.txt"\n'; touch "llm-wiki/tools/a b.txt"
                                                    lint_clean "block-list tracks and paths with spaces"
mkdir test && touch test/x;                         lint_has "undocumented top-level folder" "repo-map: test is missing from the tree"
mkdir llm-wiki/assets && touch llm-wiki/assets/x;   lint_has "undocumented vault folder" "repo-map: llm-wiki/assets is missing from the tree"
git rm -q AGENTS.md;                                lint_has "repo map lists a removed entry" "the tree lists AGENTS.md, which does not exist"
printf '# nope\n' > llm-wiki/sessions/2000-01-01-0000-bad.md
                                                    lint_has "session without Handover first" "first heading must be ## Handover"
printf '# nope\n' > llm-wiki/sessions/2000-01-01-0000-bad.md
                                                    lint_has "session without a Handover section" "2000-01-01-0000-bad.md: has no ## Handover section"
rm llm-wiki/sessions/2000-01-01-0000-bad.md

echo "## stop gate (a code change needs a wiki update)"
gate "unstaged edit blocks"            2 "touch $S; echo x >> README.md"
gate "staged edit blocks"              2 "touch $S; echo x >> README.md; git add README.md"
gate "committed edit blocks"           2 "touch $S; echo x >> README.md; G commit -qam x"
gate "git mv blocks"                   2 "touch $S; git mv SPEC.md SPEC2.md"
gate "rm blocks"                       2 "touch $S; rm README.md"
gate "new untracked file blocks"       2 "touch $S; echo x > new.txt"
gate "no session update blocks"        2 "true"
gate "code + wiki update passes"       0 "touch $S; echo x >> README.md; echo '- x' >> llm-wiki/log.md"
gate "wiki-only change passes"         0 "touch $S; echo '- x' >> llm-wiki/log.md"
gate "ignored file doesn't count"      0 "touch $S; echo x > .env"
echo x >> README.md; sleep 1
gate "committing an earlier edit passes"    0 "touch $S; G commit -qam x"
rm README.md; sleep 1
gate "an earlier deletion doesn't count"    0 "touch $S"
MODE=plan gate "plan mode passes"            0 "true"
EXTRA=',"stop_hook_active":true' gate "second stop in a turn passes" 0 "true"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
