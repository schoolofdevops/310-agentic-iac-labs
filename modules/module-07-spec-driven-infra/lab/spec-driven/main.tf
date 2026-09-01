# data source: no hardcoded AMI id (C-001)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "checkout_web" {
  name_prefix   = "checkout-web-"
  image_id      = data.aws_ami.al2023.id # C-001: AMI resolved via data source, not hardcoded
  instance_type = "t3.micro"

  # SC-005 / FR-005: require IMDSv2 tokens (CKV_AWS_79) -- blocks the SSRF-to-credentials
  # pivot that IMDSv1's unsigned metadata requests allow.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "checkout_web" {
  name = "checkout-web-asg"

  # C-002: launch template wired directly into the ASG (latest version), not applied
  # independently.
  launch_template {
    id      = aws_launch_template.checkout_web.id
    version = "$Latest"
  }

  # SC-003 / FR-003: peak bounded to 2x the 2-instance steady-state baseline, not a
  # round-number guess.
  min_size = 2
  max_size = 4

  # SC-001 / FR-001: long enough to survive a cold-boot dnf install + httpd start on a
  # slow mirror, short enough that a genuinely broken instance doesn't linger for minutes.
  health_check_grace_period = 180
  health_check_type         = "EC2"

  # SC-002 / FR-002: kill the oldest launch template version first so a mid-rollout
  # instance running the newest code is never the one picked during routine scale-in.
  termination_policies = ["OldestLaunchTemplate", "OldestInstance", "Default"]

  # SC-004 / FR-004: cooldown shortened from the provider's 5-minute default so the ASG
  # can react to a real flash-sale spike.
  default_cooldown = 90

  availability_zones = ["us-east-1a"]
}

# SC-004 / FR-004: target tracking on average CPU with headroom before saturation.
resource "aws_autoscaling_policy" "checkout_web_cpu" {
  name                   = "checkout-web-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.checkout_web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 55
  }
}
