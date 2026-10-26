#!/usr/bin/env bash
# Controls for release-push-tag.sh: every refusal happens before any push, for
# the stated reason. gh is a shell function and git runs in a throwaway
# repository, so no case touches the network or this checkout's config.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=scripts/release-push-tag.sh
source "$ROOT/scripts/release-push-tag.sh"

pass=0
fail=0
url="$RELEASE_REMOTE_URL"

# Run "$@" in a subshell (die exits it); require failure with REASON on stderr.
expect_refusal() {
  local label="$1" reason="$2"
  shift 2
  if ("$@") >"$WORK/out" 2>"$WORK/err"; then
    echo "[FAIL] expected refusal: $label" >&2
    fail=$((fail + 1))
  elif ! grep -qF -- "$reason" "$WORK/err"; then
    echo "[FAIL] $label: refused for a different reason (wanted: $reason)" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  else
    echo "[ok] refuses: $label"
    pass=$((pass + 1))
  fi
}

expect_success() {
  local label="$1"
  shift
  if ("$@") >"$WORK/out" 2>"$WORK/err"; then
    echo "[ok] accepts: $label"
    pass=$((pass + 1))
  else
    echo "[FAIL] expected success: $label" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  fi
}

# A throwaway repository; HOME points at a directory whose .gitconfig the
# isolated git must ignore.
repo="$WORK/repo"
git init -q -b main "$repo"
mkdir -p "$WORK/home"
export HOME="$WORK/home"

# --- credential -------------------------------------------------------------
no_token() { unset GH_TOKEN; require_push_credential; }
empty_token() { GH_TOKEN="" require_push_credential; }
expect_refusal "credential: GH_TOKEN unset" "GH_TOKEN is required" no_token
expect_refusal "credential: GH_TOKEN empty" "GH_TOKEN is required" empty_token

# gh sees only GH_TOKEN: other token variables are removed and its stored
# logins are hidden behind an empty config directory.
only_gh_token() {
  GH_TOKEN=t GITHUB_TOKEN=other GH_HOST=example.invalid GH_CONFIG_DIR="$HOME/.config/gh"
  require_push_credential
  [[ -z "${GITHUB_TOKEN+x}" && -z "${GH_HOST+x}" ]] || exit 1
  [[ "$GH_CONFIG_DIR" != "$HOME/.config/gh" && -d "$GH_CONFIG_DIR" && -z "$(ls -A "$GH_CONFIG_DIR")" ]] || exit 1
}
expect_success "credential: only GH_TOKEN reaches gh" only_gh_token

# --- transport ---------------------------------------------------------------
# A global rewrite of https to ssh would send the push down origin's path.
printf '[url "git@github.com:"]\n\tinsteadOf = https://github.com/\n' >"$HOME/.gitconfig"
# The fixture must bite plain git, or the next control proves nothing.
if [[ "$(cd "$repo" && git ls-remote --get-url "$url")" == "$url" ]]; then
  echo "[FAIL] fixture: global insteadOf does not rewrite plain git" >&2
  fail=$((fail + 1))
fi
global_rewrite() { cd "$repo" && require_isolated_transport "$url"; }
expect_success "transport: global insteadOf ignored" global_rewrite

injected_rewrite() {
  cd "$repo"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.git@github.com:.insteadOf GIT_CONFIG_VALUE_0=https://github.com/
  [[ "$(git ls-remote --get-url "$url")" != "$url" ]] || exit 1 # the fixture rewrites
  require_isolated_transport "$url"
}
expect_success "transport: injected GIT_CONFIG_* rewrite ignored" injected_rewrite

repo_rewrite() {
  cd "$repo" && git config url.git@github.com:.insteadOf https://github.com/
  require_isolated_transport "$url"
}
expect_refusal "transport: repository insteadOf" "rewrites URLs or sets credentials" repo_rewrite
git -C "$repo" config --unset url.git@github.com:.insteadOf

repo_pushinsteadof() {
  cd "$repo" && git config url.git@github.com:.pushInsteadOf https://github.com/
  require_isolated_transport "$url"
}
expect_refusal "transport: repository pushInsteadOf" "rewrites URLs or sets credentials" repo_pushinsteadof
git -C "$repo" config --unset url.git@github.com:.pushInsteadOf

repo_helper() {
  cd "$repo" && git config credential.helper osxkeychain
  require_isolated_transport "$url"
}
expect_refusal "transport: repository credential helper" "rewrites URLs or sets credentials" repo_helper
git -C "$repo" config --unset credential.helper

included_rewrite() {
  printf '[url "git@github.com:"]\n\tinsteadOf = https://github.com/\n' >"$WORK/included"
  cd "$repo" && git config include.path "$WORK/included"
  require_isolated_transport "$url"
}
expect_refusal "transport: rewrite through an included file" "rewrites URLs or sets credentials" included_rewrite
git -C "$repo" config --unset include.path
rm -f "$HOME/.gitconfig"

# --- bypass ------------------------------------------------------------------
valid_ruleset='{
  "name": "Tag Publish Protection", "target": "tag", "source_type": "Repository",
  "source": "lanytehq/crucible", "enforcement": "active",
  "conditions": {"ref_name": {"exclude": [], "include": ["refs/tags/v*"]}},
  "rules": [{"type": "creation"}, {"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "update"}],
  "bypass_actors": [{"actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}],
  "current_user_can_bypass": "always"
}'
with_ruleset() {
  local body="$1" detail_rc="${2:-0}"
  gh() {
    case "${*: -1}" in
    'repos/lanytehq/crucible/rulesets?per_page=100') printf '%s\n' '[[{"id":123,"name":"Tag Publish Protection"}]]' ;;
    repos/lanytehq/crucible/rulesets/123)
      [[ "$detail_rc" == 0 ]] || return "$detail_rc"
      printf '%s\n' "$body"
      ;;
    *) return 2 ;;
    esac
  }
  require_bypass_now
}
expect_success "bypass: full policy and always" with_ruleset "$valid_ruleset"
for value in '"pull_requests_only"' '"never"' 'null'; do
  expect_refusal "bypass: current_user_can_bypass $value" "not 'always'; refusing to push" \
    with_ruleset "$(jq ".current_user_can_bypass = $value" <<<"$valid_ruleset")"
done
expect_refusal "bypass: field absent" "not 'always'; refusing to push" \
  with_ruleset "$(jq 'del(.current_user_can_bypass)' <<<"$valid_ruleset")"
expect_refusal "bypass: policy weakened, credential may bypass" "does not match the full publication policy" \
  with_ruleset "$(jq '.bypass_actors = []' <<<"$valid_ruleset")"
expect_refusal "bypass: ruleset read fails" "the ruleset was not checked" \
  with_ruleset "$valid_ruleset" 1

# --- remote state -------------------------------------------------------------
# A local bare repository stands in for the fixed URL.
bare="$WORK/remote.git"
git init -q --bare -b main "$bare"
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
git -C "$repo" push -q "$bare" main
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
on_main() { cd "$repo" && require_on_remote_main "$bare" "$(git rev-parse HEAD~1)"; }
expect_success "remote: tagged commit on main" on_main
off_main() { cd "$repo" && require_on_remote_main "$bare" "$(git rev-parse HEAD)"; }
expect_refusal "remote: tagged commit not on main" "is not on main" off_main
fetch_fails() { cd "$repo" && require_on_remote_main "$WORK/absent.git" "$(git rev-parse HEAD)"; }
expect_refusal "remote: main cannot be fetched" "could not fetch main" fetch_fails

absent_tag() { cd "$repo" && require_remote_tag_absent "$bare" v1.2.3; }
expect_success "remote: tag absent" absent_tag
git -C "$repo" tag v1.2.3 HEAD~1
git -C "$repo" push -q "$bare" refs/tags/v1.2.3
present_tag() { cd "$repo" && require_remote_tag_absent "$bare" v1.2.3; }
expect_refusal "remote: tag already exists" "already exists" present_tag
unreadable() { cd "$repo" && require_remote_tag_absent "$WORK/absent.git" v1.2.3; }
expect_refusal "remote: tag list unreadable is not absence" "could not read tags" unreadable

# Deletion: absent tag refused, unreadable list refused, present tag removed.
with_bare_url() { cd "$repo" && delete_remote_tag "$bare" "$1"; }
expect_refusal "delete: remote tag absent" "nothing to delete" with_bare_url v9.9.9
delete_unreadable() { cd "$repo" && delete_remote_tag "$WORK/absent.git" v1.2.3; }
expect_refusal "delete: tag list unreadable" "nothing was deleted" delete_unreadable
expect_success "delete: present tag removed" with_bare_url v1.2.3
if [[ -n "$(git -C "$bare" tag -l v1.2.3)" ]]; then
  echo "[FAIL] delete: remote tag still present" >&2
  fail=$((fail + 1))
fi
bad_arg() { main --force; }
expect_refusal "arguments: unknown argument" "unknown argument" bad_arg

echo
echo "release push controls: ${pass} passed, ${fail} failed"
((fail == 0))
