# Feature Specification: Checkout Web Tier Autoscaling

## Requirements

### Functional Requirements

- FR-001: The Auto Scaling Group's health check grace period MUST be long enough to
  survive the checkout app's real boot sequence (a `dnf install` of httpd plus service
  start on a cold instance, which can run well past a minute on a slow mirror), so a
  slow-starting-but-healthy instance is never killed as if it had failed. It must not be
  so long that a genuinely broken instance survives for minutes before being replaced.
- FR-002: Scale-in MUST prefer terminating the oldest launch template version first, so a
  mid-rollout instance running the newest code is never the one picked to die during a
  routine scale-in.
- FR-003: Capacity MUST be bounded to a known, justified peak, not an arbitrary round
  number. This tier's measured peak is 2x its steady-state baseline of 2 instances.
- FR-004: Scale-out MUST target average CPU utilization with headroom before saturation,
  and MUST set an explicit cooldown short enough to react to a real flash-sale traffic
  spike, not the provider's 5-minute default built for slower-moving workloads.
- FR-005: Instance metadata MUST require IMDSv2 tokens. IMDSv1 has no request signing and
  is a known SSRF pivot path into instance credentials.

### Constraints

- C-001: No account-specific value may be hardcoded into a resource block.
- C-002: The launch template and Auto Scaling Group must be wired together, not left as
  two independently-applied resources.

## Success Criteria

- SC-001: `health_check_grace_period` = 180
- SC-002: `termination_policies` = `["OldestLaunchTemplate", "OldestInstance", "Default"]`
- SC-003: `min_size` = 2, `max_size` = 4
- SC-004: an `aws_autoscaling_policy` of type `TargetTrackingScaling`, predefined metric
  `ASGAverageCPUUtilization`, `target_value` = 55, and the ASG's own `default_cooldown` = 90
- SC-005: the launch template's `metadata_options.http_tokens` = `"required"`
- SC-006: checkov passes `CKV_AWS_79` (IMDSv2) on the launch template -- see the note below
