output "public_ip" {
  value = aws_instance.this.public_ip
}

output "game_url" {
  value = "http://${aws_instance.this.public_ip}:5000"
}

output "grafana_url" {
  value = "http://${aws_instance.this.public_ip}:3000"
}

output "prometheus_url" {
  value = "http://${aws_instance.this.public_ip}:9090"
}

output "grafana_password" {
  value     = random_password.grafana.result
  sensitive = true
}
