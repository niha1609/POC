# security group creation and attcahing in ecs, alb etc
data "aws_availability_zones" "available_zones" {
  state = "available"
}

# ALB Security Group: Edit to restrict access to the application
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.default.cidr_block, 8, 2 + count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.default.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.default.id
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}

resource "aws_eip" "gateway" {
  count      = 2
  vpc        = true
  #depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "gateway" {
  count         = 2
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.gateway.*.id, count.index)
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.gateway.*.id, count.index)
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_security_group" "lb" {
  name        = "testapp-load-balancer-security-group"
  description = "controls access to the ALB"
  vpc_id      = aws_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = var.app_port
    to_port     = var.app_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# this security group for ecs - Traffic to the ECS cluster should only come from the ALB
resource "aws_security_group" "ecs_sg" {
  name        = "testapp-ecs-tasks-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = aws_vpc.default.id

  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "default" {
  name            = "example-lb"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.lb.id]
}

resource "aws_lb_target_group" "poc" {
  name        = "example-target-group"
  port        = 8096
  protocol    = "HTTP"
  vpc_id      = aws_vpc.default.id
  target_type = "ip"

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    protocol = "HTTP"
    matcher = "200"
    path = "/"
    interval = 30
  }
}

resource "aws_lb_listener" "poc" {
  load_balancer_arn = aws_lb.default.id
  port              = "8096"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.poc.id
    type             = "forward"
  }
}

# Define provider for AWS
provider "aws" {
  access_key = "AKIAZSG3R3NXIBEFZ3EW"
  secret_key = "T2ZbU8U2oRvQI2ile8VmFU19BsV5bY40RXlHvPBf"
  region = "us-east-1"  # Update with your desired region
  #shared_credentials_files = "~/.aws/credentials"
}

# Create an ECS cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "poc-cluster"  # Update with your desired cluster name
}

# Create an ECS service
resource "aws_ecs_service" "my_service" {
  name            = "POC-service"  # Update with your desired service name
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  desired_count   = 2
  launch_type     = "EC2"  # Use "EC2" if you prefer EC2 launch type

  network_configuration {
    subnets         = aws_subnet.private.*.id  # Update with your desired subnets
    security_groups = [aws_security_group.ecs_sg.id]  # Update with your desired security groups
    #assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.poc.arn
    container_name   = "my-container"
    container_port   = 8096
  }

  depends_on = [aws_lb_listener.poc, aws_iam_role_policy_attachment.my_task_execution_policy_attachment]
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = "poc-task-definition"  # Update with your desired task definition name
  cpu                      = 1024
  memory                   = 2048
  container_definitions    = <<DEFINITION
[
  {
    "name": "my-container",
    "image": "657590442862.dkr.ecr.us-east-1.amazonaws.com/poc:latest",
    "portMappings": [
      {
        "containerPort": 8096,
        "hostPort" : 8096,
        "protocol": "tcp"
      }
    ],
    "memory": 2048,
    "cpu": 1024
  }
]
DEFINITION
  requires_compatibilities = ["EC2"]  # Use "EC2" if you prefer EC2 launch type
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.my_task_execution_role.arn
}

# Create an ECR repository
#resource "aws_ecr_repository" "my_repository" {
#  name = "POC"  # Update with your desired repository name
#}

# Create IAM role for task execution
resource "aws_iam_role" "my_task_execution_role" {
  name = "Test"  # Update with your desired role name
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
POLICY
}

# Attach policy to IAM role for task execution
resource "aws_iam_role_policy_attachment" "my_task_execution_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.my_task_execution_role.name
}
