# Release rails: signed-tag creation and verification (no binaries shipped).
# Operator procedure: RELEASE_CHECKLIST.md (repo root).
# Policy: docs/policies/release-signing-manual-baseline-policy.md
#
# Environment variables (full details in the scripts/release-*.sh headers):
#   LANYTE_CRUCIBLE_RELEASE_TAG      the release tag (required; never derived from VERSION or git)
#   LANYTE_CRUCIBLE_DECERNOR_BIN     absolute path to decernor >= 0.1.8 (required for
#                                    anchor and tag verification; no PATH fallback)
#   LANYTE_CRUCIBLE_GPG_HOMEDIR      dedicated signing keyring (required to sign; never the
#                                    default keyring)
#   LANYTE_CRUCIBLE_PGP_KEY_ID       key id/email/fingerprint for signing
#   LANYTE_CRUCIBLE_TAGGER_NAME      tagger name stamped on the tag object
#   LANYTE_CRUCIBLE_TAGGER_EMAIL     tagger email stamped on the tag object
#   LANYTE_CRUCIBLE_ALLOW_NON_MAIN   set to 1 to allow tagging off main
#
# Retired, unprefixed, and 3leaps release variables are refused, not ignored
# (scripts/release-env.sh).

.PHONY: release-tag
release-tag: ## Create signed release tag with safety checks
	@./scripts/release-tag.sh

.PHONY: release-verify-tag
release-verify-tag: ## Verify the tag against the committed pin in a throwaway keyring
	@./scripts/release-verify-tag.sh

.PHONY: release-check-anchors
release-check-anchors: ## Re-derive the fingerprint anchors with decernor and compare
	@./scripts/release-derive-anchors.sh --check

.PHONY: release-guard-tag-version
release-guard-tag-version: ## Verify release tag matches VERSION file
	@./scripts/release-guard-tag-version.sh

.PHONY: release-check-goneat-pin
release-check-goneat-pin: ## Admit goneat CI digests: check them against goneat's signed SHA256SUMS (needs minisign; CI trusts the digest)
	@./scripts/release-verify-goneat-pin.sh

.PHONY: release-guard-tag-ruleset
release-guard-tag-ruleset: ## Verify the live version-tag ruleset, bypass actors included (gh via org-root direnv)
	@./scripts/release-guard-tag-ruleset.sh
