# Bootstrap

This is the only supported first-deploy sequence. It matches [README.md](../../README.md); the notes explain what each phase is doing and what "stuck" looks like.

## Preflight

Complete the checks in [00-environment.md](00-environment.md#preflight-commands). At minimum:

- `aws sts get-caller-identity` succeeds in the intended account.
- `tofu version` is 1.13.x (1.8+ is required for `.tofu` files).
- `aws --version` reports AWS CLI v2.
- `git --version` works, or the module cache is already present.
- The GPU quota `L-39F81BFB` is at least 1 in `ap-southeast-1`.
- No other `tofu apply`/`destroy` is running against `infra/terraform.tfstate`.

## The sequence

```bash
tofu -chdir=infra/ init
tofu -chdir=infra/ plan -exclude=module.sagemaker_unified_studio
tofu -chdir=infra/ apply -exclude=module.sagemaker_unified_studio
tofu -chdir=infra/ plan
tofu -chdir=infra/ apply
```

### 1. `tofu init`

Downloads the providers recorded in `infra/.terraform.lock.hcl` (AWS 6.73.0, AWSCC 1.110.0, external 2.4.2, random 3.9.1, time 0.14.2) and clones the AWS-IA module at commit `457c2b3b46389f00219971145098a142101b43f2` into `infra/.terraform/modules/`.

Expected: "OpenTofu has been successfully initialized". If Git is unavailable, initialization of the Git module fails even if the provider downloads succeed; do not delete the existing `.terraform/` cache.

### 2–3. First phase, excluding the domain module

The `.tofu` files create the VPC and subnets in the root module, then the AWS-IA module's `modules/blueprint` validates the subnet IDs with `for_each`. On a fresh apply the subnet IDs are unknown until the VPC exists, so the module's graph cannot be expanded (`Invalid for_each argument`). Excluding `module.sagemaker_unified_studio` also excludes everything that depends on it, leaving the network and the domain-independent project execution role chain for this phase.

Expected creates: `aws_vpc`, `aws_internet_gateway`, two public and two private `aws_subnet`s, public/private route tables, four route-table associations, the NAT gateway, and the `${var.name_prefix}-smus-project-role` IAM role with its policy attachment, inline PassRole policy, and the short `time_sleep`. No DataZone domain, project, or space yet.

Do not use `-target` instead, and do not remove the `-exclude` phase.

### 4–5. Full plan and apply

Once the network is in state, the module's `for_each` keys are known. The full apply creates, roughly in this order:

1. The DataZone/SageMaker Unified Studio domain, its IAM roles, the tooling S3 bucket, the Tooling blueprint, and the module's model-governance project/profile.
2. `data.external.deployer_profile`: polls `aws datazone get-user-profile` until the DataZone user profile exists (the model-governance project creates it).
3. `data.external.project_sagemaker_domain`: polls `aws sagemaker list-domains` for the per-project SageMaker AI domain (`d-...`), whose name contains the project ID.
4. The default project profile, the create-project policy grant, the project execution role (already created in the first phase if this is a fresh stack), and the project.
5. `aws_sagemaker_user_profile.deployer`: creates the project-domain SageMaker user profile with the DataZone profile ID as its name.
6. `aws_sagemaker_space.user`: creates the private JupyterLab space on `ml.g4dn.xlarge` with the GPU SageMaker Distribution image, the `AmazonDataZoneUser`/project/domain tags, and the replacement tracker.

The lookups can make `plan`/`apply` appear idle for several minutes. They poll rather than sleep once. Do not interrupt the first full apply; the project's SageMaker domain is created asynchronously by the project environment.

## Post-apply

- `tofu -chdir=infra state list` should show the domain module resources, the external lookups, the project, the user profile, and the space.
- Open the SageMaker Unified Studio console, select the project, open **Code spaces**, and start `${var.name_prefix}-gpu-space`. Starting the space can fail on a quota or permission problem even though apply succeeded; see [03-troubleshooting.md](03-troubleshooting.md).
- Upload [00-pytorch-gpu-example.ipynb](../../notebook/00-pytorch-gpu-example.ipynb) to the space and choose **Restart and run all cells**. Expected output includes `GPU acceleration is available in this notebook!` and a `cuda:0` tensor. See [04-verification.md](04-verification.md) for the full checklist.

## Re-running on an existing stack

The same five commands are safe. The first phase is a no-op when the network is already in state; the full plan should be clean. If the plan proposes ownership/sharing changes to the space, the `terraform_data.space_identity` tracker will force a replacement rather than the provider's silent in-place update.

## When it fails

Do not destroy the stack to clear a single object. Go to [03-troubleshooting.md](03-troubleshooting.md), identify the exact error, and use import or a targeted replacement. Preserve `infra/terraform.tfstate`; it is the only record of the deployed resources.
