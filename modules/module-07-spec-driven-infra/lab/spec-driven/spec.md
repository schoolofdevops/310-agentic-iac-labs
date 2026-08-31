# Feature Specification: Build Artifacts Bucket

**Feature Branch**: `001-build-artifacts-bucket`

**Created**: 2026-08-31

**Status**: Draft

**Input**: User description: "Give me an S3 bucket for storing build artifacts."

This is the real ask, verbatim, the way it would show up as a ticket. It says nothing about
access, retention, or encryption. That silence is the point of this lab.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CI uploads a build artifact (Priority: P1)

A CI job finishes a build and needs to store the resulting artifact somewhere durable, so a later
job (or a human debugging a failed deploy) can retrieve it.

**Why this priority**: Without this, there is no bucket, and nothing else in this spec matters.

**Independent Test**: Can be tested by writing an object to the bucket and reading it back.

**Acceptance Scenarios**:

1. **Given** the bucket exists, **When** CI writes an object to it, **Then** the object is stored
   and retrievable by key.
2. **Given** an object was overwritten, **When** the previous version is requested, **Then** it is
   still recoverable (versioning is on).

---

### User Story 2 - Nobody outside the org can read a build artifact (Priority: P1)

Build artifacts often contain internal paths, dependency lists, and sometimes debug symbols. None
of that should be reachable from the public internet.

**Why this priority**: A public artifacts bucket is a real, common incident. This is not
hypothetical caution.

**Independent Test**: Can be tested by asserting the bucket's public-access-block settings are all
`true` and that no bucket policy grants `Principal: "*"`.

**Acceptance Scenarios**:

1. **Given** the bucket, **When** an anonymous, unauthenticated request is made to any object,
   **Then** it is denied.

### Edge Cases

- What happens when someone tries to make an object public by hand, after the bucket exists? The
  public-access-block setting must still block it, since it applies at the bucket level, not per
  object.
- What happens to an artifact nobody has touched in a year? Out of scope for this spec, lifecycle
  rules are a separate future spec, not required here.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bucket MUST have versioning enabled, so an overwritten artifact is still
  recoverable.
- **FR-002**: The bucket MUST have all four public-access-block settings enabled (block public
  ACLs, block public policy, ignore public ACLs, restrict public buckets).
- **FR-003**: The bucket MUST use server-side encryption (SSE) by default, so an object written
  without an explicit encryption header is still encrypted at rest.
- **FR-004**: The bucket MUST be tagged with `purpose = "build-artifacts"` and `managed_by =
  "terraform"`, so it's identifiable in a resource inventory without opening the console.
- **FR-005**: The bucket name MUST be provided as a variable, not hardcoded, so the same module can
  be reused per environment.

### Constraints

- **C-001**: The bucket MUST NOT have a public bucket policy attached, under any circumstance.
- **C-002**: The module MUST NOT hardcode any account-specific value (account ID, region) as a
  literal inside a resource block; those come from variables or provider configuration.

### Key Entities

- **Artifacts bucket**: An S3 bucket holding build outputs, versioned, encrypted, private,
  tagged for inventory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `aws_s3_bucket_versioning` for the bucket has `status = "Enabled"`.
- **SC-002**: `aws_s3_bucket_public_access_block` for the bucket has all four settings `true`.
- **SC-003**: `aws_s3_bucket_server_side_encryption_configuration` is present and set to a real
  algorithm (`AES256` or `aws:kms`).
- **SC-004**: The bucket's tags include `purpose = "build-artifacts"` and `managed_by =
  "terraform"`.
- **SC-005**: `checkov -d .` reports zero failed checks on the specific rules this spec maps to:
  `CKV_AWS_21` (versioning), `CKV2_AWS_6` (public access block), `CKV_AWS_19` (encrypted at rest).
  This spec does not claim a fully clean `checkov` run. Checkov's ruleset also covers access
  logging, lifecycle rules, cross-region replication, and KMS-specifically-required encryption,
  none of which this spec asked for. A spec's acceptance criteria only cover what the spec's
  author thought to write down; that gap is exactly why the policy gate in M09 still runs after
  this, a spec does not replace it.

## Assumptions

- Single AWS account, single region, no cross-region replication required for this spec.
- No lifecycle/retention policy required yet, a separate spec would cover that if the org decides
  artifacts need to expire.
- This module targets Floci (Tier 1 emulation) for the course lab; the same Terraform applies
  unmodified against real AWS.
