# Verification

Use this after the five-command bootstrap and again before teardown. It verifies both the OpenTofu state and the AWS-side objects, and complements the tested human procedure in [README.md](../../README.md).

## 1. State and addresses

```bash
tofu -chdir=infra state list
```

Expect entries for the network, the domain module (`module.sagemaker_unified_studio...`), the project (`module.project...`), the external lookups, `aws_sagemaker_user_profile.deployer`, and `aws_sagemaker_space.user`. The exact count varies with the module version, but the domain, project, profile, and space must be present.

```bash
tofu -chdir=infra state show 'aws_sagemaker_space.user'
```

Confirm:

- `space_settings.jupyter_lab_app_settings.default_resource_spec.instance_type` is `ml.g4dn.xlarge`.
- `sagemaker_image_arn` ends in `sagemaker-distribution-gpu` for the deployed region.
- `space_sharing_settings.sharing_type` is `Private`.
- `ownership_settings.owner_user_profile_name` is a UUID.
- The three `AmazonDataZone*` tags are present.

## 2. AWS-side checks

Replace `<d-id>` with the per-project SageMaker domain ID and `<dzd-id>` with the SageMaker Unified Studio domain ID from state or the console.

```bash
aws sagemaker list-spaces \
  --domain-id <d-id> \
  --region ap-southeast-1 \
  --query 'Spaces[].[SpaceName,SpaceSharingSettingsSummary.SharingType,OwnershipSettingsSummary.OwnerUserProfileName]' \
  --output table
```

Expected: `${var.name_prefix}-gpu-space`, `Private`, owner UUID.

```bash
aws sagemaker list-user-profiles \
  --domain-id <d-id> \
  --region ap-southeast-1 \
  --query 'UserProfiles[].[UserProfileName,Status]' \
  --output table
```

Expected: the owner UUID with a SageMaker status of `InService` (or `Pending` while it is being created).

```bash
aws sagemaker list-tags-for-resource \
  --resource-arn <space-arn> \
  --region ap-southeast-1
```

Expected: `AmazonDataZoneUser` (the UUID), `AmazonDataZoneProject`, `AmazonDataZoneDomain`.

```bash
aws service-quotas get-service-quota \
  --service-code sagemaker \
  --quota-code L-39F81BFB \
  --region ap-southeast-1 \
  --query 'Quota.{Name:QuotaName,Value:Value}'
```

Expected: `Value` is at least 1 before starting the space.

## 3. Console and space

1. Open the SageMaker Unified Studio console, select the project `${var.name_prefix}-project`, and open **Code spaces**.
2. Confirm `${var.name_prefix}-gpu-space` is listed as a private JupyterLab space.
3. Start the space. A quota or permission failure here is covered in [03-troubleshooting.md](03-troubleshooting.md); a successful apply does not guarantee a successful start.

## 4. Notebook and GPU

1. Upload [00-pytorch-gpu-example.ipynb](../../notebook/00-pytorch-gpu-example.ipynb) into the started space.
2. Choose **Restart and run all cells**.
3. Expected output includes:

```text
GPU acceleration is available in this notebook!
```

and a result containing `device='cuda:0'` / `device(type='cuda', index=0)`. Run `!nvidia-smi` in an additional cell if you want to see the driver and CUDA versions; the GPU image should report the T4.

If the notebook reports CPU, confirm the opened space is the Terraform-created GPU space, not the auto-created default JupyterLab space, and confirm `sagemaker_image_arn` in state is the GPU ARN.

## 5. Teardown acceptance

Teardown is destructive. Only run it when the human asks for it.

1. Stop the GPU space in the SMUS console. A running app blocks cleanup.
2. Empty the module's tooling bucket. Its name is in state:

```bash
tofu -chdir=infra state show 'module.sagemaker_unified_studio.aws_s3_bucket.domain[0]'
aws s3 rm s3://<tooling-bucket> --recursive
```

3. Destroy:

```bash
tofu -chdir=infra destroy
```

The project module's destroy path deletes project environments using the AWS CLI; keep AWS CLI v2 available and credentials aligned. Domain deletion is asynchronous, so the command can run for 15–30 minutes.

4. Verify:

```bash
tofu -chdir=infra state list
aws sagemaker list-domains --region ap-southeast-1 --query 'Domains[].[DomainId,DomainName]' --output table
```

Expected: empty state, no demo domain/space left. The DataZone user profile is removed with the domain; it is not separately managed by Terraform.

## Acceptance checklist

- [ ] `tofu -chdir=infra plan` is clean after the bootstrap.
- [ ] `aws_sagemaker_space.user` exists with the GPU ARN, `Private`, and owner UUID.
- [ ] `aws_sagemaker_user_profile.deployer` exists in the project domain.
- [ ] The space is listed in Code spaces and starts.
- [ ] The notebook reports CUDA available.
- [ ] Before destroy: space stopped and tooling bucket empty.
- [ ] After destroy: state empty and no demo domain/space remains.
