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
  requires_compatibilities = ["FARGATE"]  # Use "EC2" if you prefer EC2 launch type
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.my_task_execution_role.arn
}

# Create an ECS service
resource "aws_ecs_service" "my_service" {
  name            = "POC-service"  # Update with your desired service name
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"  # Use "EC2" if you prefer EC2 launch type

  network_configuration {
    subnets         = ["subnet-12345678", "subnet-87654321"]  # Update with your desired subnets
    security_groups = ["sg-12345678"]  # Update with your desired security groups
    assign_public_ip = true
  }
}

# Create an ECR repository
resource "aws_ecr_repository" "my_repository" {
  name = "test"  # Update with your desired repository name
}

# Create IAM role for task execution
resource "aws_iam_role" "my_task_execution_role" {
  name = "POC"  # Update with your desired role name
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
