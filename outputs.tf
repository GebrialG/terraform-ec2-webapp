output "alb_dns_name" {
  description = "Public DNS name of the load balancer"
  value       = aws_lb.web.dns_name
}

output "instance_ids" {
  description = "IDs of the web instances"
  value       = aws_instance.web[*].id
}