variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "name_prefix" {
  type    = string
  default = "sagemaker-ai-demo"
}

data "aws_availability_zones" "available" {}

variable "subnet1_public_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "subnet2_public_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "subnet1_private_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "subnet2_private_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "space_instance_type" {
  description = "Instance type for the SageMaker space (default: single NVIDIA T4 GPU)"
  type        = string
  default     = "ml.g4dn.xlarge"
}

variable "space_image_arn" {
  description = "GPU SageMaker Distribution image ARN (region-specific)"
  type        = string
  default     = "arn:aws:sagemaker:ap-southeast-1:022667117163:image/sagemaker-distribution-gpu"
}
