data "external" "deployer_profile" {
  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    domain_id='${module.sagemaker_unified_studio.domain_id}'
    user_arn='${data.aws_caller_identity.current.arn}'
    for _ in $(seq 1 60); do
      profile_id=$(aws datazone get-user-profile \
        --domain-identifier "$${domain_id}" \
        --user-identifier "$${user_arn}" \
        --type IAM \
        --region '${var.region}' \
        --query 'id' --output text 2>/dev/null || true)
      if [ -n "$${profile_id}" ] && [ "$${profile_id}" != "None" ]; then
        printf '{"id":"%s"}' "$${profile_id}"
        exit 0
      fi
      sleep 10
    done
    echo "Timed out waiting for the DataZone user profile of $${user_arn}" >&2
    exit 1
  EOT
  ]
}

data "external" "project_sagemaker_domain" {
  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    project_id='${module.project.project_id}'
    for _ in $(seq 1 60); do
      domain_id=$(aws sagemaker list-domains \
        --region '${var.region}' \
        --max-results 100 \
        --query "Domains[?contains(DomainName, '$${project_id}')].DomainId | [0]" \
        --output text 2>/dev/null || true)
      if [ -n "$${domain_id}" ] && [ "$${domain_id}" != "None" ]; then
        printf '{"domain_id":"%s"}' "$${domain_id}"
        exit 0
      fi
      sleep 15
    done
    echo "Timed out waiting for the SageMaker AI domain of project $${project_id}" >&2
    exit 1
  EOT
  ]
}

resource "aws_sagemaker_user_profile" "deployer" {
  domain_id         = data.external.project_sagemaker_domain.result.domain_id
  user_profile_name = data.external.deployer_profile.result.id

  user_settings {
    execution_role = aws_iam_role.project_execution.arn
  }

  tags = {
    AmazonDataZoneUser    = data.external.deployer_profile.result.id
    AmazonDataZoneProject = module.project.project_id
    AmazonDataZoneDomain  = module.sagemaker_unified_studio.domain_id
  }
}

resource "terraform_data" "space_identity" {
  triggers_replace = [
    data.external.deployer_profile.result.id,
    "Private",
  ]
}

resource "aws_sagemaker_space" "user" {
  domain_id  = data.external.project_sagemaker_domain.result.domain_id
  space_name = "${var.name_prefix}-gpu-space"

  ownership_settings {
    owner_user_profile_name = data.external.deployer_profile.result.id
  }

  space_sharing_settings {
    sharing_type = "Private"
  }

  space_settings {
    app_type = "JupyterLab"

    jupyter_lab_app_settings {
      default_resource_spec {
        instance_type       = var.space_instance_type
        sagemaker_image_arn = var.space_image_arn
      }
    }
  }

  tags = {
    AmazonDataZoneUser    = data.external.deployer_profile.result.id
    AmazonDataZoneProject = module.project.project_id
    AmazonDataZoneDomain  = module.sagemaker_unified_studio.domain_id
  }

  lifecycle {
    replace_triggered_by = [terraform_data.space_identity]
  }

  depends_on = [aws_sagemaker_user_profile.deployer]
}
