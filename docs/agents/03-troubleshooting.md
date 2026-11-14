# Troubleshooting

Find the exact error string, apply the smallest safe fix, and preserve `infra/terraform.tfstate`. Do not destroy the stack to clear one object.

## Error map

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Invalid for_each argument` in `.terraform/modules/.../modules/blueprint/main.tf`, mentioning `data.aws_subnet.validation` | The fresh VPC and subnets are created in the same apply as the module's subnet `for_each` (upstream issue #41) | Run the five commands from [01-bootstrap.md](01-bootstrap.md). The first phase must exclude `module.sagemaker_unified_studio`. Do not edit the module. |
| `Cannot create a user profile for existing principalId: 'AID...'` | An `aws_datazone_user_profile` resource has been re-added, or old state still manages one. The module's model-governance project already created the DataZone profile. | Remove the `aws_datazone_user_profile` resource from the configuration; it is not part of the supported stack. Do not import one unless you deliberately manage it. |
| `creating SageMaker AI Space: ... ValidationException: UserProfile [arn:...:user-profile/d-.../<id>] does not exist` | The **project-domain** SageMaker user profile is missing. The DataZone profile alone is not enough. | Check `tofu -chdir=infra state list` for `aws_sagemaker_user_profile.deployer`; if the portal created the profile first, import it: `tofu -chdir=infra import 'aws_sagemaker_user_profile.deployer' '<d-id>/<profile-id>'`. Otherwise let the full apply reach the profile resource before the space. `aws sagemaker list-user-profiles --domain-id <d-id>` shows what exists. |
| `no identity-based policy allows the sagemaker:UpdateSpace action` (or `CreateApp`/`DeleteApp`) | The space is missing the `AmazonDataZoneUser` tag, is not `Private`, or the profile tags are missing. `SageMakerStudioUserIAMDefaultExecutionPolicy` grants these actions only under those conditions. | Confirm with `aws sagemaker list-spaces --domain-id <d-id>` and `aws sagemaker list-tags-for-resource --resource-arn <space-arn>`. Restore the tags and Private sharing in `space.tofu`; re-apply. The tracker will replace the space if ownership/sharing changed. |
| `Invalid count argument` on `aws_sagemaker_user_profile` or another resource | A conditional `count` was introduced that depends on an `external` result unknown until apply. | Remove the condition. The supported configuration creates the user profile unconditionally. Do not add another `-exclude` phase to work around it. |
| `Studio JupyterLab Apps running on ml.g4dn.xlarge instances is 0 Apps` on **Start space** | GPU quota is 0 in this account/region; apply succeeds, start fails. | Request quota `L-39F81BFB` in the correct region (see [README.md](../../README.md) for the tested caveat). Confirm with `aws service-quotas get-service-quota --service-code sagemaker --quota-code L-39F81BFB --region ap-southeast-1`. |
| `ResourceLimitExceeded` on a different Studio size or job type | A different, unrelated SageMaker quota is 0. | The error names the exact quota. Request that name; the GPU space quota is not a substitute. |
| `tofu import` says the resource already exists / state drift | The object exists remotely but not in state (or vice versa). | Import the specific object, then `tofu plan`. Never destroy the whole stack for one object. |
| `external` lookup times out: "Timed out waiting for the DataZone user profile" or "Timed out waiting for the SageMaker AI domain" | AWS CLI credentials/region do not match the provider, the project environment is still provisioning, or the profile/domain was never created. | Check `aws sts get-caller-identity`, `AWS_PROFILE`, `AWS_REGION`, and the provider region. Re-run the apply; the lookups poll. Do not remove the lookups. |
| `BucketNotEmpty` during destroy | The module's tooling bucket still has objects; `force_destroy` is disabled. | Stop the space, then `aws s3 rm s3://<tooling-bucket> --recursive`, then retry `tofu destroy`. |
| Space cannot be deleted or apply is blocked by a running space | A running JupyterLab app holds the space. | Stop the space in the SMUS console, or stop its app, then retry. |
| A plan repeatedly proposes ownership/sharing changes to the space, but apply "succeeds" and the diff returns | The provider's `UpdateSpace` path ignores `ownership_settings`/`space_sharing_settings`; that is why `terraform_data.space_identity` exists. | Keep the tracker. Force a replacement if needed: `tofu -chdir=infra apply -replace='aws_sagemaker_space.user'`. |
| A managed DataZone user profile remains after destroy, or an old configuration keeps trying to recreate it | The provider's DataZone user-profile delete is a no-op; profiles are removed with their domain. | Do not rely on destroying a profile resource. Remove it from configuration and let domain deletion remove the profile. |
| `aws: command not found` or DataZone commands fail | AWS CLI v2 is missing, too old, or not on `PATH`. | Install AWS CLI v2 and verify `aws --version`; the `external` lookups and the project destroy path require it. |
| `tofu: command not found` | OpenTofu is not on the agent's `PATH` (common in sandboxes). | Find the host installation or install OpenTofu 1.13.x; do not delete state while the tool is missing. |

## Diagnostics

Run these before changing anything. Replace placeholders with IDs from state or the AWS console.

```bash
tofu -chdir=infra state list
tofu -chdir=infra state show 'aws_sagemaker_space.user'
tofu -chdir=infra state show 'aws_sagemaker_user_profile.deployer'

aws sagemaker list-domains \
  --region ap-southeast-1 \
  --query 'Domains[].[DomainId,DomainName]' --output table

aws sagemaker list-user-profiles \
  --domain-id <d-id> \
  --region ap-southeast-1 \
  --query 'UserProfiles[].[UserProfileName,Status]' --output table

aws sagemaker list-spaces \
  --domain-id <d-id> \
  --region ap-southeast-1 \
  --query 'Spaces[].[SpaceName,SpaceSharingSettingsSummary.SharingType,OwnershipSettingsSummary.OwnerUserProfileName]' \
  --output table

aws sagemaker list-tags-for-resource \
  --resource-arn <space-arn> \
  --region ap-southeast-1

aws datazone get-user-profile \
  --domain-identifier <dzd-id> \
  --user-identifier <caller-arn> \
  --type IAM \
  --region ap-southeast-1
```

`dzd-...` is the SageMaker Unified Studio domain; `d-...` is the per-project SageMaker AI domain. Mixing them is a common cause of "profile does not exist".

## Importing instead of recreating

Use imports for objects that already exist. Import does not create or modify the remote object; it only records it in state.

```bash
# Project-domain SageMaker user profile (the one CreateSpace requires)
tofu -chdir=infra import 'aws_sagemaker_user_profile.deployer' '<d-id>/<profile-id>'

# GPU space (ARN form)
tofu -chdir=infra import 'aws_sagemaker_space.user' \
  'arn:aws:sagemaker:<region>:<account>:space/<d-id>/<space-name>'
```

The DataZone user profile is intentionally not managed here. If an old state or an experimental configuration still has an `aws_datazone_user_profile` resource, remove it from configuration rather than recreating it; the model-governance project owns that profile's lifecycle.

After any import:

```bash
tofu -chdir=infra plan
```

The plan should show no replace for the imported object. If it wants to replace it, stop and inspect the ID/name rather than approving.

## Do not

- Do not run `tofu destroy` because one resource is in the wrong state.
- Do not delete `infra/terraform.tfstate` or `.terraform/` to "start clean" without a deliberate, human-approved teardown.
- Do not edit the downloaded AWS-IA module to bypass the two-phase workaround.
- Do not add conditional counts around `external` lookups; they cannot be known at plan time.
- Do not reuse the quota ARN from [README.md](../../README.md) across accounts or regions. Use the quota code and verify in the target account.
