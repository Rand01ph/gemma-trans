# Repository instructions

Before planning or changing code, branches, CI, build configuration, or release state, read:

1. [Development and release workflow](docs/development/workflow-policy.md) — the normative, reusable policy.
2. [GemmaTrans project configuration](docs/development/project-workflow.md) — repository-specific settings and migration status.

These linked documents are part of the instructions for this repository. Read them explicitly; Markdown links do not load their contents automatically. Apply them to implementation, reviews, documentation, and release operations. Explicit user instructions take precedence; record any authorized exception and its verification limits.

Essential rules:

- Formal releases come from a verified commit on `main`; ongoing development belongs on `develop`.
- Use short-lived branches and PRs. Do not force-push shared branches or move published release tags.
- Xcode Cloud owns remote compilation, tests, signing, and release builds. Do not introduce a second GitHub Actions build pipeline.
- A formal `vX.Y.Z` tag identifies the exact source of the validated artifact; tagging must not rebuild it.
- Report compile, archive, upload, processing, review, and availability as separate states. Never call a queued or archived build published.
- Preserve user data and existing worktrees. Keep test app identities and settings separate from the installed production app.
- Keep credentials out of source, logs, command output, and release documents; use authorized secret references.
- Public release text describes only the current shipping version. Do not disclose unreleased features or development plans.

For release work, also read [Release runbook](docs/releasing.md). Consult migration status before changing workflow triggers or branch protection. Do not remove a working check before its replacement has passed and is required on the PR.
