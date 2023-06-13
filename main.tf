# security group creation and attcahing in ecs, alb etc

# ALB Security Group: Edit to restrict access to the application
resource "aws_vpc" "default" {
  cidr_block = "172.31.0.0/16"
}

resource "aws_security_group" "alb-sg" {
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
    security_groups = [aws_security_group.alb-sg.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Define provider for AWS
provider "aws" {
  region = "us-east-1"  # Update with your desired region
}

# Create an ECS cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"  # Update with your desired cluster name
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = "my-task-definition"  # Update with your desired task definition name
  container_definitions    = <<DEFINITION
[
  {
    "name": "my-container",
    "image": "657590442862.dkr.ecr.us-east-1.amazonaws.com/test:latest",
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80,
        "protocol": "tcp"
      }
    ],
    "memory": 512,
    "cpu": 256
  }
]
DEFINITION
  requires_compatibilities = ["EC2"]  # Use "EC2" if you prefer EC2 launch type
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.my_task_execution_role.arn
}

# Create an ECS service
resource "aws_ecs_service" "my_service" {
  name            = "POC-service"  # Update with your desired service name
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  desired_count   = 1
  launch_type     = "EC2"  # Use "EC2" if you prefer EC2 launch type

  network_configuration {
    subnets         = ["subnet-015484ab2a5e58149", "subnet-01d31b21ce5911add"]  # Update with your desired subnets
    security_groups = ["sg-0797f2482623cc87e"]  # Update with your desired security groups
    #assign_public_ip = true
  }
}

# Create an ECR repository
resource "aws_ecr_repository" "my_repository" {
  name = "poc"  # Update with your desired repository name
}

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
