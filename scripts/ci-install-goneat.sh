#!/usr/bin/env bash
# ci-install-goneat.sh - Install goneat by digest and its format backends (CI)
#
# goneat comes from the committed digest pin (release-fetch-tool.sh); the
# backends it orchestrates are installed at fixed versions. Appends the tool
# directory to GITHUB_PATH. Usage: ci-install-goneat.sh

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
tool_dir="$(mktemp -d "$RUNNER_TEMP/goneat.XXXXXX")"
./scripts/release-fetch-tool.sh goneat linux_amd64 "$tool_dir" >/dev/null
echo "$tool_dir" >>"$GITHUB_PATH"

# goneat orchestrates yamlfmt (yaml/json) + prettier (markdown)
go install github.com/google/yamlfmt/cmd/yamlfmt@v0.16.0
echo "$(go env GOPATH)/bin" >>"$GITHUB_PATH"
npm install -g prettier@3.9.6
"$tool_dir/goneat" version | head -n1
"$(go env GOPATH)/bin/yamlfmt" --version
prettier --version
