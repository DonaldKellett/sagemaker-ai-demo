data "aws_caller_identity" "current" {}

locals {
  project_name = "${var.name_prefix}-project"
}

resource "aws_iam_role_policy_attachment" "provisioning_admin" {
  role       = reverse(split("/", module.sagemaker_unified_studio.provisioning_role_arn))[0]
  policy_arn = "arn:aws:iam::aws:policy/SageMakerStudioAdminIAMDefaultExecutionPolicy"
}

module "default_project_profile" {
  source = "git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git//modules/default-project-profile?ref=457c2b3b46389f00219971145098a142101b43f2"

  domain_id             = module.sagemaker_unified_studio.domain_id
  provisioning_role_arn = module.sagemaker_unified_studio.provisioning_role_arn
  vpc_id                = aws_vpc.sagemaker_ai_demo_vpc.id
  subnet_ids = [
    aws_subnet.sagemaker_ai_demo_subnet1_private.id,
    aws_subnet.sagemaker_ai_demo_subnet2_private.id,
  ]

  depends_on = [aws_iam_role_policy_attachment.provisioning_admin]
}

module "create_project_grant" {
  source = "git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git//modules/policy-grant-create-project?ref=457c2b3b46389f00219971145098a142101b43f2"

  domain_id           = module.sagemaker_unified_studio.domain_id
  domain_unit_id      = module.sagemaker_unified_studio.domain_root_unit_id
  project_profile_ids = [module.default_project_profile.project_profile_id]
  all_users           = true
}

locals {
  smus_services = [
    "datazone.amazonaws.com", "sagemaker.amazonaws.com", "glue.amazonaws.com",
    "bedrock.amazonaws.com", "scheduler.amazonaws.com", "lakeformation.amazonaws.com",
    "airflow-serverless.amazonaws.com", "athena.amazonaws.com",
    "redshift.amazonaws.com", "emr-serverless.amazonaws.com",
    "elasticmapreduce.amazonaws.com",
  ]
}

resource "aws_iam_role" "project_execution" {
  name = "${var.name_prefix}-smus-project-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = local.smus_services }
      Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetContext", "sts:SetSourceIdentity"]
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "project_execution" {
  role       = aws_iam_role.project_execution.name
  policy_arn = "arn:aws:iam::aws:policy/SageMakerStudioUserIAMDefaultExecutionPolicy"
}

resource "aws_iam_role_policy" "project_pass_role" {
  name = "PassRole"
  role = aws_iam_role.project_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = aws_iam_role.project_execution.arn
      Condition = {
        StringEquals = {
          "aws:ResourceAccount" = "$${aws:PrincipalAccount}"
          "iam:PassedToService" = local.smus_services
        }
      }
    }]
  })
}

resource "time_sleep" "project_role_ready" {
  depends_on      = [aws_iam_role_policy_attachment.project_execution, aws_iam_role_policy.project_pass_role]
  create_duration = "10s"
}

module "project" {
  source = "git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git//modules/project?ref=457c2b3b46389f00219971145098a142101b43f2"

  domain_id          = module.sagemaker_unified_studio.domain_id
  project_name       = local.project_name
  project_profile_id = module.default_project_profile.project_profile_id
  project_role       = aws_iam_role.project_execution.arn

  depends_on = [
    module.create_project_grant,
    time_sleep.project_role_ready
  ]
}

module "project_membership" {
  source = "git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git//modules/project-membership?ref=457c2b3b46389f00219971145098a142101b43f2"

  domain_id  = module.sagemaker_unified_studio.domain_id
  project_id = module.project.project_id

  project_owners = {}
}
