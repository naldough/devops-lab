variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "devops-lab"
}

variable "instance_type" {
  type    = string
  default = "t3.small" # 2 GB RAM: enough for K3s plus the API
}

