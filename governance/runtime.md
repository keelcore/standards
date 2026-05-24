# Runtime and Orchestration Standards

These rules govern container design, orchestration, deployment, and policy compliance. They are non-negotiable unless
explicitly superseded by a signed ADR.

**Maturity:** Required **Version:** 1.0.0 **Last Reviewed:** 2026-03-09

## Containers and Artifacts

### Versioning

1. All published artifacts (container images, packages, binaries) use Semantic Versioning (SemVer). Unversioned or
   date-stamped-only artifacts are prohibited.
2. The artifact tag is the SemVer string. The `latest` tag must not be used in staging or production manifests.

### Container Design

1. One process per container. Process supervisors (supervisord, s6) and multi-process containers are prohibited except
   for sidecar patterns enforced by the service mesh.
2. Multiple entry points (different commands/args) for the same image are allowed where the image provides genuinely
   distinct modes (e.g., `serve` and `migrate`). Each entry point must be documented in the image's README.
3. Containers run as a non-root user. `USER root` in the final image stage is prohibited.
4. Container filesystems are read-only where possible. Writable directories are explicitly declared and limited to
   ephemeral paths (`/tmp`, named volumes).

### Artifact Metadata

1. Every artifact must embed: Git commit SHA, repository URL, branch, build timestamp, and SemVer. These are queryable
   via a `version` subcommand or equivalent metadata endpoint.
2. Artifacts are tagged with: SemVer, commit SHA short form, and environment target (`dev`, `staging`, `prod`).
   Promotion from one environment to the next reuses the same image digest — it is never rebuilt.

### Registry Lifecycle

1. Image promotion lifecycle: `dev` registry → `staging` registry → `prod` registry. Artifacts flow in one direction; no
   artifact is pulled from `prod` into `dev`.
2. Artifacts not promoted to `staging` within 30 days of build are expired from the `dev` registry.
3. Artifacts in `prod` are retained for a minimum of 12 months.

### Security Scanning

1. CVE scanning runs on every artifact before it is pushed to any registry. The approved scanner is documented in the
   internal vendor registry.
2. Critical CVEs block promotion. High CVEs require a documented exception with an accepted remediation timeline
   (maximum 30 days). Medium and below are tracked but do not block promotion.
3. A Software Bill of Materials (SBOM) in SPDX or CycloneDX format is generated for every release artifact. The SBOM is
   attached to the release and stored alongside the artifact digest.

## Orchestration

### Declarative Manifests

1. All workloads are declared via version-controlled orchestration manifests (Kubernetes YAML, Helm charts, Kustomize
   overlays, or equivalent). Manual `kubectl apply` of locally generated YAML in production is prohibited.
2. Manifests are validated (lint + schema check) as a required CI step before merge.

### Probes

1. Every container that serves traffic must define `livenessProbe`, `readinessProbe`, and optionally `startupProbe`.
2. Readiness probes must reflect actual service readiness (e.g., database connection established, cache warm) not just
   process startup.
3. Liveness probe failures must trigger a container restart, not a silent hang. Liveness probe endpoints must not have
   side effects.

### Resource Quotas

1. Every workload declares `resources.requests` and `resources.limits` for CPU and memory. Pods without resource
   declarations are rejected by admission control.
2. Resource requests must reflect measured steady-state usage. Over-requesting by more than 3× the p99 measured usage
   requires justification.
3. Namespace-level `ResourceQuota` and `LimitRange` objects are applied to all tenant namespaces.

### High Availability

1. All production workloads run in a minimum of two availability zones. Single-zone deployments are prohibited in
   production.
2. `PodAntiAffinity` rules are configured to prevent all replicas of a deployment from scheduling onto a single node or
   zone.
3. Minimum replica count for production services is 2. Services with replica count 1 require documented justification
   and ARB approval.

## Deployment

### Deployment Strategy

1. All production deployments use a rolling, blue/green, or canary strategy. Big-bang (recreate) deploys are prohibited
   in production.
2. Deployments support rollback to the previous artifact version within 5 minutes.
3. Deployment events are logged in the audit log with: artifact version, deploy actor, environment, start time, end
   time, and outcome.

### Zero-Downtime Deployment

1. Zero-downtime deployment capability is required for all production services.
2. Traffic shaping during rollout: network load balancer or service mesh gradually shifts traffic from the old version
   to the new version. Hard cutover is prohibited.
3. APIs must be backward-compatible across a deployment window. Breaking API changes require a versioned endpoint
   strategy before the old version is retired.
4. Schema migrations (database, event schema) are non-breaking and phased:
   - Phase 1: add new column/field (backward-compatible with old code).
   - Phase 2: deploy new code that writes both old and new.
   - Phase 3: backfill and migrate data.
   - Phase 4: remove old column/field only after old code is fully retired.
5. Feature flags or service mesh routing rules are used to gate new behavior during deployment. A feature can be
   promoted or rolled back independently of the artifact version.

### Service Mesh

1. All east-west (pod-to-pod) traffic runs through the service mesh. Direct pod-to-pod communication bypassing the mesh
   is prohibited in staging and production.
2. The mesh enforces mTLS, authorization policy, and traffic observability on all managed traffic.
3. Circuit breakers and retry budgets are configured per service. Default retry-all-failures behavior is prohibited;
   retries must be limited and idempotent-safe.

### Secrets Management

1. Application secrets (database passwords, API keys, private keys) are injected at runtime from the approved secrets
   manager. Secrets must not be embedded in container images, manifests, environment variable literals, or
   version-controlled configuration.
2. Secrets are mounted as in-memory volumes or environment variables injected by the secrets sidecar/operator. Secrets
   written to the container filesystem at rest are prohibited.
3. Secret access is logged by the secrets manager. Unexpected access patterns alert the security team.

## Policy and Compliance

### Change Management

1. All infrastructure changes are managed via GitOps or a declarative change management system. Out-of-band changes
   (manual console, ad-hoc CLI) are prohibited in staging and production and will be detected and reverted by
   reconciliation.
2. Production changes require approval from at least one person who is not the change author.
3. Every production change record includes a rollback plan. Changes without a tested rollback plan are not approved.
4. CTO and ARB policy documents are archived and versioned. Historical policy versions are accessible.

### Compliance

1. The platform maintains SOC-2 Type II compliance. Evidence collection is automated where possible.
2. GDPR and CCPA requirements apply to all data processing pipelines. Privacy impact assessments are required for new
   data processing features that handle personal data.
3. A Secure Development Lifecycle (SDL) is followed: threat modeling, SAST, DAST, dependency scanning, and penetration
   testing are performed on a defined cadence.
4. ISO 27001 and NIST SP 800-53 are used as optional benchmarks to inform control selection. Controls are documented but
   full certification is optional unless contractually required.

## Do Not

- Use the `latest` tag in staging or production manifests.
- Run containers as root.
- Deploy workloads without liveness and readiness probes.
- Deploy workloads without CPU and memory resource limits.
- Run a production service with fewer than two availability zones.
- Perform big-bang (recreate) deploys in production.
- Embed secrets in images, manifests, or version-controlled configuration.
- Allow service-to-service traffic to bypass the service mesh in staging or production.
- Perform breaking schema migrations in a single phase.
- Make infrastructure changes outside of the approved GitOps workflow.
- Approve a production change without a rollback plan.
