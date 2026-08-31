# C + D — EC2 with an AMI data source + user_data, and RDS MySQL.
# This is the 3-tier app shape carried over from the 2025 course labs.
# Floci backs aws_instance with a real amazonlinux:2023 container and
# aws_db_instance with a real mysql:8.0 container, so the "connect to the DB
# and load the schema" steps from the old lab work unchanged, at zero cost.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = <<-USERDATA
    #!/bin/bash
    dnf install -y httpd php php-mysqlnd
    systemctl enable --now httpd
  USERDATA
  tags                   = { Name = "spike-web" }
}
resource "aws_db_subnet_group" "db" {
  name       = "spike-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}
resource "aws_security_group" "db" {
  name   = "spike-db"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}
resource "aws_db_instance" "app" {
  identifier             = "spike-devopsdb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "devopsdb"
  username               = "devopsadmin"
  password               = "ChangeMe12345!" # deliberately bad — M06/M09 fix this
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
}
output "ami_id" {
  value = data.aws_ami.al2023.id
}
output "web_private_ip" {
  value = aws_instance.web.private_ip
}
output "db_endpoint" {
  value = aws_db_instance.app.endpoint
}
