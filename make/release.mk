# Release rails: signed-tag creation and verification (no binaries shipped).
# Operator procedure: RELEASE_CHECKLIST.md (repo root).
# Policy: docs/policies/release-signing-manual-baseline-policy.md
#
# Environment variables (full details in the scripts/release-*.sh headers):
#   LANYTE_CRUCIBLE_RELEASE_TAG      override tag (default: v$(cat VERSION))
#   LANYTE_CRUCIBLE_GPG_HOMEDIR      dedicated signing keyring directory
#   LANYTE_CRUCIBLE_PGP_KEY_ID       key id/email/fingerprint for signing
#   LANYTE_CRUCIBLE_TAGGER_NAME      tagger name stamped on the tag object
#   LANYTE_CRUCIBLE_TAGGER_EMAIL     tagger email stamped on the tag object
#   LANYTE_CRUCIBLE_ALLOW_NON_MAIN   set to 1 to allow tagging off main
#   LANYTE_CRUCIBLE_REQUIRE_TAG      set to 1 to make the guard fail without a tag (CI)

.PHONY: release-tag
release-tag: ## Create signed release tag with safety checks
	@./scripts/release-tag.sh

.PHONY: release-verify-tag
release-verify-tag: ## Verify signed tag signature
	@./scripts/release-verify-tag.sh

.PHONY: release-guard-tag-version
release-guard-tag-version: ## Verify release tag matches VERSION file
	@./scripts/release-guard-tag-version.sh
