data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "checkout_web" {
  name_prefix = "checkout-web-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.checkout_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "checkout_alb" {
  name_prefix = "checkout-alb-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "checkout_web" {
  name_prefix   = "checkout-web-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.checkout_web.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y httpd
    echo "checkout service ok" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "checkout-web"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "checkout" {
  name               = "checkout-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.checkout_alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "checkout_web" {
  name     = "checkout-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "checkout_web" {
  load_balancer_arn = aws_lb.checkout.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.checkout_web.arn
  }
}

resource "aws_autoscaling_group" "checkout_web" {
  name_prefix         = "checkout-web-"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.checkout_web.arn]

  min_size         = 2
  max_size         = 6
  desired_capacity = 2

  health_check_type         = "ELB"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.checkout_web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "checkout-web"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "checkout_web_cpu" {
  name                   = "checkout-web-target-tracking-cpu"
  autoscaling_group_name = aws_autoscaling_group.checkout_web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

output "alb_dns_name" {
  value = aws_lb.checkout.dns_name
}
