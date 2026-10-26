#!/usr/bin/env bash
# release-env.sh - Explicit release inputs (3leaps/crucible PDR-0008 §2.3, §2.4)
#
# Source this file; it defines functions only.
#
# - refuse_legacy_release_env: fail if a retired, unprefixed, or other
#   repository's release variable is set, so an inherited name never silently
#   wins or is silently ignored.
# - require_release_tag: print LANYTE_CRUCIBLE_RELEASE_TAG, which must be a
#   canonical vMAJOR.MINOR.PATCH tag. There is no default from VERSION, git
#   describe, or the branch.
# - resolve_release_decernor: set RELEASE_DECERNOR_BIN from
#   LANYTE_CRUCIBLE_DECERNOR_BIN, an absolute path to a regular, executable,
#   non-symlink decernor >= RELEASE_DECERNOR_MIN_VERSION. There is no fallback
#   to PATH or to another variable.
# - require_signing_keyring: set RELEASE_GNUPGHOME from
#   LANYTE_CRUCIBLE_GPG_HOMEDIR, a dedicated signing keyring. The default
#   keyring is never used. It is refused whether named by gpgconf's default
#   or by the account's own .gnupg, so a relocated HOME cannot hide it.
# - require_signing_gpg_program: fail unless git would sign with plain `gpg`,
#   since a configured gpg.program can ignore GNUPGHOME.

RELEASE_DECERNOR_MIN_VERSION="0.1.8"

RELEASE_RETIRED_VARIABLES=(
    RELEASE_TAG
    CRUCIBLE_RELEASE_TAG
    CRUCIBLE_GPG_HOMEDIR
    CRUCIBLE_PGP_KEY_ID
    CRUCIBLE_TAGGER_NAME
    CRUCIBLE_TAGGER_EMAIL
    CRUCIBLE_ALLOW_NON_MAIN
    CRUCIBLE_REQUIRE_TAG
    CRUCIBLE_DECERNOR_BIN
    DECERNOR_BIN
    LANYTE_CRUCIBLE_REQUIRE_TAG
    THREELEAPS_CRUCIBLE_RELEASE_TAG
    THREELEAPS_CRUCIBLE_GPG_HOMEDIR
    THREELEAPS_CRUCIBLE_PGP_KEY_ID
    THREELEAPS_CRUCIBLE_DECERNOR_BIN
)

refuse_legacy_release_env() {
    local name found=()
    for name in "${RELEASE_RETIRED_VARIABLES[@]}"; do
        if [[ -n "${!name+set}" ]]; then
            found+=("$name")
        fi
    done
    if ((${#found[@]})); then
        echo "error: retired, unprefixed, or other-repository release variable set: ${found[*]}" >&2
        echo "hint: unset it; release inputs use the LANYTE_CRUCIBLE_ prefix (RELEASE_CHECKLIST.md)" >&2
        return 1
    fi
}

require_release_tag() {
    local tag="${LANYTE_CRUCIBLE_RELEASE_TAG:-}"
    if [[ -z "$tag" ]]; then
        echo "error: LANYTE_CRUCIBLE_RELEASE_TAG is required (e.g. v1.2.3); the tag is never derived" >&2
        return 1
    fi
    if ! [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "error: invalid release tag '$tag' (expected vMAJOR.MINOR.PATCH)" >&2
        return 1
    fi
    printf '%s\n' "$tag"
}

resolve_release_decernor() {
    local candidate="${LANYTE_CRUCIBLE_DECERNOR_BIN:-}" short extended version
    if [[ -z "$candidate" ]]; then
        echo "error: LANYTE_CRUCIBLE_DECERNOR_BIN is required (absolute path to decernor >= ${RELEASE_DECERNOR_MIN_VERSION})" >&2
        return 1
    fi
    if ! [[ "$candidate" == /* && -f "$candidate" && ! -L "$candidate" && -x "$candidate" ]]; then
        echo "error: LANYTE_CRUCIBLE_DECERNOR_BIN must be an absolute path to a regular, executable, non-symlink file" >&2
        return 1
    fi
    short="$("$candidate" version 2>/dev/null)" || {
        echo "error: decernor identity check failed" >&2
        return 1
    }
    if ! [[ "$short" =~ ^decernor\ ((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$ ]]; then
        echo "error: LANYTE_CRUCIBLE_DECERNOR_BIN is not decernor (reported '${short%%$'\n'*}')" >&2
        return 1
    fi
    version="${BASH_REMATCH[1]}"
    extended="$("$candidate" version -e 2>/dev/null)" || {
        echo "error: decernor extended identity check failed" >&2
        return 1
    }
    local labels=("Version" "Commit" "Build Date" "Go Version" "Gofulmen" "Crucible") line count=0
    while IFS= read -r line; do
        if ((count >= ${#labels[@]})) || ! [[ "$line" =~ ^${labels[count]}:[[:space:]]+[^[:space:]] ]]; then
            echo "error: invalid decernor extended identity" >&2
            return 1
        fi
        count=$((count + 1))
    done <<<"$extended"
    if ((count != ${#labels[@]})) || ! [[ "$extended" =~ ^Version:[[:space:]]+${version//./\\.}($'\n') ]]; then
        echo "error: invalid decernor extended identity" >&2
        return 1
    fi
    local have want i
    IFS=. read -r -a have <<<"$version"
    IFS=. read -r -a want <<<"$RELEASE_DECERNOR_MIN_VERSION"
    for i in 0 1 2; do
        if ((have[i] > want[i])); then
            break
        fi
        if ((have[i] < want[i])); then
            echo "error: decernor >= ${RELEASE_DECERNOR_MIN_VERSION} required (found ${version})" >&2
            return 1
        fi
    done
    # shellcheck disable=SC2034 # Consumed by scripts that source this file.
    RELEASE_DECERNOR_BIN="$candidate"
}

# Directories the dedicated keyring must not be: the default keyring as the
# signing gpg resolves it (GNUPGHOME unset), and the account's .gnupg read
# from the user database. gpgconf derives its default from HOME, so a HOME
# pointed elsewhere would hide the real keyring; the account home cannot be
# redirected that way.
account_home() {
    local dir
    dir="$(python3 -I -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)' 2>/dev/null)" ||
        dir="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)" || true
    [[ -n "$dir" ]] || return 1
    printf '%s\n' "$dir"
}

physical() {
    if [[ -d "$1" ]]; then
        (cd "$1" && pwd -P)
    else
        printf '%s\n' "$1"
    fi
}

default_gpg_homedirs() {
    local gpgconf_home home
    gpgconf_home="$(env -u GNUPGHOME gpgconf --list-dirs homedir 2>/dev/null)" || return 1
    [[ -n "$gpgconf_home" ]] || return 1
    home="$(account_home)" || return 1
    physical "$gpgconf_home"
    physical "$home/.gnupg"
}

require_signing_keyring() {
    local homedir="${LANYTE_CRUCIBLE_GPG_HOMEDIR:-}" resolved default_home
    if [[ -z "$homedir" ]]; then
        echo "error: LANYTE_CRUCIBLE_GPG_HOMEDIR is required; the default GPG keyring is never used" >&2
        echo "hint: point it at a dedicated signing keyring directory" >&2
        return 1
    fi
    if ! [[ "$homedir" == /* && -d "$homedir" && ! -L "$homedir" ]]; then
        echo "error: LANYTE_CRUCIBLE_GPG_HOMEDIR must be an absolute path to an existing, non-symlink directory" >&2
        return 1
    fi
    resolved="$(cd "$homedir" && pwd -P)"
    local defaults
    if ! defaults="$(default_gpg_homedirs)"; then
        echo "error: cannot resolve the default GPG keyring (gpgconf and the account home); refusing to sign" >&2
        return 1
    fi
    while IFS= read -r default_home; do
        if [[ "$resolved" == "$default_home" ]]; then
            echo "error: LANYTE_CRUCIBLE_GPG_HOMEDIR resolves to the default GPG keyring; use a dedicated keyring" >&2
            return 1
        fi
    done <<<"$defaults"
    if [[ -n "${GNUPGHOME:-}" ]]; then
        if ! [[ -d "$GNUPGHOME" ]] || [[ "$(cd "$GNUPGHOME" && pwd -P)" != "$resolved" ]]; then
            echo "error: GNUPGHOME is set to a different directory than LANYTE_CRUCIBLE_GPG_HOMEDIR" >&2
            echo "hint: unset GNUPGHOME, or set it to the same keyring" >&2
            return 1
        fi
    fi
    # shellcheck disable=SC2034 # Consumed by scripts that source this file.
    RELEASE_GNUPGHOME="$resolved"
}

# git signs through gpg.program; any value other than plain gpg may not honor
# GNUPGHOME. The signing command also passes -c gpg.program=gpg.
require_signing_gpg_program() {
    local configured
    configured="$(git config --get gpg.program 2>/dev/null || true)"
    if [[ -n "$configured" && "$configured" != "gpg" ]]; then
        echo "error: git gpg.program is '${configured}'; release signing requires plain gpg" >&2
        echo "hint: unset it for this repository, or sign from a clean git config" >&2
        return 1
    fi
}
