provider "aws" {
  region = "ap-south-1"
}

# Security Group for EC2
resource "aws_security_group" "web_sg" {
  name        = "webapp-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
resource "aws_lb" "web_lb" {
  name               = "blue-green-lb"
  load_balancer_type = "application"
  subnets            = var.subnets
  security_groups    = [aws_security_group.web_sg.id]
}

# Target Groups for Blue & Green
resource "aws_lb_target_group" "blue_tg" {
  name     = "blue-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green_tg" {
  name     = "green-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Launch Template (EC2 with Docker)
resource "aws_launch_template" "web_template" {
  name_prefix   = "web-bluegreen-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install docker.io -y
    systemctl start docker
    systemctl enable docker
    docker pull ${var.docker_image}:latest
    docker run -d -p 80:80 ${var.docker_image}:latest
  EOF
  )
}

# Auto Scaling Groups
resource "aws_autoscaling_group" "blue_asg" {
  desired_capacity     = 1
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = var.subnets
  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.blue_tg.arn]
}

resource "aws_autoscaling_group" "green_asg" {
  desired_capacity     = 0
  min_size             = 0
  max_size             = 2
  vpc_zone_identifier  = var.subnets
  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.green_tg.arn]
}

# CodeDeploy Application
resource "aws_codedeploy_app" "web_app" {
  name             = "webapp-bluegreen"
  compute_platform = "Server"
}

# CodeDeploy Deployment Group (Blue-Green)
resource "aws_codedeploy_deployment_group" "web_group" {
  app_name              = aws_codedeploy_app.web_app.name
  deployment_group_name = "webapp-deploy-group"
  service_role_arn      = var.codedeploy_role_arn

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                        = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  load_balancer_info {
    target_group_pair_info {
      target_groups = [
        { name = aws_lb_target_group.blue_tg.name },
        { name = aws_lb_target_group.green_tg.name }
      ]
    }
  }

  auto_scaling_groups = [aws_autoscaling_group.blue_asg.name]
}
