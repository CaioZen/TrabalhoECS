terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------
# SECURITY GROUP
# -----------------------------------------------------

resource "aws_security_group" "app_sg" {
  name        = "app-fullstack-sg"
  description = "Libera portas para Backend e Banco"
  vpc_id      = data.aws_vpc.default.id

  # Porta do backend (8000)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Porta do banco (5432) 
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída liberada
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------
# CLUSTER
# -----------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "cluster-fullstack"
}

# -----------------------------------------------------
# TASK DEFINITION
# -----------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = "task-fullstack"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 1024
  memory = 2048

  container_definitions = jsonencode([

    # -------------------------------------------------
    # BANCO DE DADOS
    # -------------------------------------------------
    {
        name      = "db"
        image     = "postgres:16"
        essential = true

        environment = [
            { name = "POSTGRES_USER",     value = "user" },
            { name = "POSTGRES_PASSWORD", value = "123456" },
            { name = "POSTGRES_DB",       value = "banco" }
        ]

        portMappings = [
            { containerPort = 5432 }
        ]

        healthCheck = {
            command     = ["CMD-SHELL", "pg_isready -U user"]
            interval    = 5
            timeout     = 3
            retries     = 10
            startPeriod = 20
        }
    },


    # -------------------------------------------------
    # BACKEND
    # -------------------------------------------------
    {
      name      = "backend"
      image     = "caio120/fullstack-app:latest"
      essential = true

      dependsOn = [
        { containerName = "db", condition = "HEALTHY" }
      ]

      environment = [
        { name = "DB_HOST",     value = "127.0.0.1" },
        { name = "DB_PORT",     value = "5432" },
        { name = "DB_USER",     value = "user" },
        { name = "DB_PASSWORD", value = "123456" },
        { name = "DB_NAME",     value = "banco" }
      ]

      portMappings = [
        { containerPort = 8000 }
      ]
    }

  ])
}

# -----------------------------------------------------
# SERVICE
# -----------------------------------------------------

resource "aws_ecs_service" "app_service" {
  name            = "service-fullstack"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = true
  }
}

# -----------------------------------------------------
# OUTPUT
# -----------------------------------------------------

output "acesso_backend" {
  value = "Acesse http://IP_PUBLICO:8000"
}