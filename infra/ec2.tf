data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile = aws_iam_instance_profile.this.name

  associate_public_ip_address = true

  # Require IMDSv2 session tokens (Checkov CKV_AWS_79 / tfsec aws-ec2-enforce-http-token-imds)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker
              systemctl enable docker
              systemctl start docker
              # K3s (lightweight Kubernetes) - runs the API; Traefik ingress serves ports 80/443
              curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
              EOF

  tags = {
    Name = "${var.project}-ec2"
  }
}
