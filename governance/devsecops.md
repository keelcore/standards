# DevSecOps Standards

These rules govern repository controls, release integrity, security scanning, and supply-chain metadata for every
project that follows the keelcore standards. They are non-negotiable unless explicitly superseded by a signed ADR.

**Maturity:** Required **Version:** 1.0.0 **Last Reviewed:** 2026-10-31

Baselines: OpenSSF Scorecard, OpenSSF OSPS Baseline, SLSA v1.0 build track, NIST SSDF (SP 800-218), Kubernetes Pod
Security Standards (restricted). Each rule carries a severity — **H** high, **M** medium, **L** low — which orders
remediation when a project audits against this document: all H before any M, all M before any L.

Related: [`ci.md`](ci.md) (workflow and script rules), [`security.md`](security.md) (IAM, encryption, data),
[`runtime.md`](runtime.md) (containers and orchestration), [`release-policy.md`](release-policy.md) (tagging).

---

## Repository Controls

1. **(H)** The default branch is protected by a ruleset: pull request required, required status checks, signed commits,
   CODEOWNERS review, force-push and deletion blocked. Release tags (`v*`) are protected against deletion and update.
   Repository admins may be bypass actors; every bypass is logged by the platform.
2. **(H)** CODEOWNERS names owners that exist (users or teams with repository access). An owner that does not resolve
   makes the CODEOWNERS review rule unsatisfiable.
3. **(H)** The deployment environment used by the release workflow has protection rules: a required reviewer and
   deployments restricted to release tags. A workflow comment claiming human approval is not a control.
4. **(H)** Private vulnerability reporting is enabled whenever `SECURITY.md` names it as a reporting channel.
5. **(H)** Secret scanning, push protection, Dependabot alerts, and Dependabot security updates are enabled.

## Release Integrity

1. **(H)** Images are signed and attested by digest before any mutable alias tag (`latest`, `vX`, `vX.Y`) is moved to
   them. A failed release never leaves an alias on an unsigned image.
2. **(H)** Signing and attestation are idempotent: a retry that hits an existing transparency-log entry for the same
   digest (Rekor `409`) is confirmed with `cosign verify` / `cosign verify-attestation` and treated as success.
3. **(H)** Build provenance (SLSA) covers every released artifact: binaries, archives, and each image digest, with the
   attestation pushed to the registry next to the image.
4. **(H)** Every image carries its own SBOM, generated from that image (or the exact binary it contains) and attested to
   that digest. One source-tree SBOM attached to several images is non-compliant.
5. **(M)** The release workflow verifies its own output as its last step: `cosign verify` and
   `cosign verify-attestation` on every published digest and blob.

## Scanning Gates

1. **(H)** Dependency vulnerabilities: a reachability-aware scanner (`govulncheck` for Go; `osv-scanner` otherwise)
   runs as a required CI check.
2. **(H)** Static analysis for security (SAST): CodeQL plus a language security linter (`gosec` for Go) run in CI. A
   general linter (e.g. staticcheck) does not satisfy this rule.
3. **(H)** Every image is scanned before it is pushed (Grype or equivalent); the release fails on any fixable CRITICAL
   or HIGH finding.
4. **(H)** Code that parses untrusted input (tokens, signatures, config, headers, hostnames) has native fuzz targets,
   and CI runs a short fuzz pass on each change.
5. **(M)** OpenSSF Scorecard runs on a schedule with SARIF upload, guarding the repository controls against regression.
6. **(M)** Workflows are security-linted (`zizmor`, `actionlint`) in CI.
7. **(M)** Rendered deployment manifests (Helm charts) are policy-scanned (`kubescape` or `checkov`), not only
   schema-validated.
8. **(M)** Dependency licenses are checked against an allowlist (`go-licenses` for Go).

Scanner versions are pinned, installed by a `scripts/ci/setup-*.sh` script with checksum or module-version
verification, and invoked through a Makefile target per [`ci.md`](ci.md).

## Base Images and Dependencies

1. **(H)** Every `FROM` that is not `scratch` or a locally built stage is pinned by digest (`image:tag@sha256:…`).
2. **(H)** Dependabot (or Renovate) covers every ecosystem in the repository: language modules, GitHub Actions, container
   base images, and git submodules.

## Deployment Artifacts

1. **(H)** Chart defaults point at the registry and repository the release actually publishes to; the default tag is
   the chart's `appVersion`; an `image.digest` value, when set, takes precedence over the tag.
2. **(H)** Every documented chart value is wired into the templates. A value that selects an image flavor actually
   selects it.
3. **(M)** Containers ship with default resource requests and limits, so runtime memory limits (e.g. `GOMEMLIMIT`) can
   be derived.

## Reproducibility and Time

1. **(L)** Images are published for every supported architecture (at least `linux/amd64` and `linux/arm64`) under one
   manifest list.
2. **(L)** Build metadata is reproducible: timestamps such as `org.opencontainers.image.created` derive from
   `SOURCE_DATE_EPOCH` (the commit time), never wall-clock time.
3. **(L)** Repositories are UTC internally. Every timestamp a script, test, workflow, or binary writes is UTC: `date -u`
   in shell, `.UTC()` in Go, `TZ=UTC` exported by the Makefile and set in workflow `env`. Local time zones never leak
   into artifacts, logs, or test expectations.
4. **(L)** Non-exploitable CVEs reported against a release are published as OpenVEX statements.

## Project Audits

A project audits itself against this document and records the result as a plan in `docs/plans/`, one finding per
non-compliant rule, ordered by severity. Rules that do not apply (e.g. no container images) are listed as not
applicable with a one-line reason.
