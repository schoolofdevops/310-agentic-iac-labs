# The flagship build for this module: an RDS instance with a real, non-default
# parameter group attached. The parameter group is the whole point, not a prop:
# it is the piece whose exact resource shape you'd normally have to look up.
resource "aws_db_subnet_group" "db" {
  name       = "m05-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_parameter_group" "app" {
  name   = "m05-mysql8-slowlog"
  family = "mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  parameter {
    name  = "long_query_time"
    value = "2"
  }
}

resource "aws_db_instance" "app" {
  identifier              = "m05-appdb"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "appdb"
  username                = "appadmin"
  password                = "ChangeMe12345!" # deliberately bad, M06/M09's problem
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  parameter_group_name    = aws_db_parameter_group.app.name
  skip_final_snapshot     = true
  storage_encrypted       = true
}

output "db_endpoint" {
  value = aws_db_instance.app.endpoint
}
output "parameter_group" {
  value = aws_db_parameter_group.app.name
}
