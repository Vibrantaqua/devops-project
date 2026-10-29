variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "snake-game"
}

variable "instance_type" {
  type        = string
  description = "t3.small is comfortable for app + Prometheus + Grafana; t3.micro works on the free plan"
  default     = "t3.small"
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.7/32"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/Vibrantaqua/snake-game.git"
}

variable "repo_branch" {
  type    = string
  default = "main"
}

variable "app_image" {
  type    = string
  default = "ghcr.io/vibrantaqua/snake-game"
}
