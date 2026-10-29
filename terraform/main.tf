terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Secrets are generated, never hard-coded or committed
resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "random_password" "app_secret" {
  length  = 32
  special = false
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_security_group" "this" {
  name        = "${var.project}-sg"
  description = "Game, SSH, Grafana and Prometheus access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Game (public)"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana from my IP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Prometheus from my IP"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg" }
}

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    app_image   = var.app_image
    app_secret  = random_password.app_secret.result
    grafana_pw  = random_password.grafana.result
  })
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project}-server" }
}
