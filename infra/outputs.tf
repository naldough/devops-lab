output "instance_id" { value = aws_instance.web.id }
output "public_ip" { value = aws_instance.web.public_ip }
output "public_dns" { value = aws_instance.web.public_dns }
output "ecr_repo_url" {
  value = aws_ecr_repository.api.repository_url
}
