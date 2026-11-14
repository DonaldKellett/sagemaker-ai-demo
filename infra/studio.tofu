locals {
  domain_name = "${var.name_prefix}-unified-studio-domain"
}

module "sagemaker_unified_studio" {
  source = "git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git?ref=457c2b3b46389f00219971145098a142101b43f2"

  domain_name = local.domain_name

  vpc_id = aws_vpc.sagemaker_ai_demo_vpc.id
  subnet_ids = [
    aws_subnet.sagemaker_ai_demo_subnet1_private.id,
    aws_subnet.sagemaker_ai_demo_subnet2_private.id,
  ]

  tags = {
    Name = local.domain_name
  }
}
