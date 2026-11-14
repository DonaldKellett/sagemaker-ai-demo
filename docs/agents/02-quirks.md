# Quirks and invariants

Read this before changing `infra/`. The configuration is deliberately shaped around several AWS-IA module and AWS provider limitations. "Simplifying" these pieces usually breaks a fresh deployment.

## Why the first phase is split

The AWS-IA module's `modules/blueprint/main.tf` builds its subnet-validation map with keys like `${region}:${subnet_id}` and uses that map as `for_each`. When the VPC and subnets are created in the same apply, the subnet IDs are unknown at plan time, so OpenTofu cannot expand the module graph and fails with `Invalid for_each argument`.

This is upstream [issue #41](https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio/issues/41), not a bug in this repository. The documented workaround is the first apply that excludes `module.sagemaker_unified_studio`. Do not replace it with `-target`, and do not patch the downloaded module: the module is pinned by commit and the cache is disposable.

## The module source is Git, not the registry

`infra/studio.tofu` and `infra/project.tofu` use:

```text
git::https://github.com/aws-ia/terraform-aws-sagemaker-unified-studio.git?ref=457c2b3b46389f00219971145098a142101b43f2
```

The module is listed on the Terraform Registry, but the OpenTofu registry does not serve it; a bare `aws-ia/sagemaker-unified-studio/aws` source with `version` will not resolve. Keep the full commit SHA. Submodules are referenced with `//modules/<name>` before `?ref=`. Changing the SHA is a deliberate upgrade; re-read the module's release notes first.

## Two different user profiles

There are two profiles, in two different domains:

- **DataZone user profile**, in the `dzd-...` domain. The module's model-governance project is created with the deployer's IAM credentials and DataZone auto-creates the deployer profile as its `created_by`. The current configuration therefore has **no** `aws_datazone_user_profile` resource; adding one races the module and fails with `Cannot create a user profile for existing principalId`.
- **SageMaker AI user profile**, in the project's `d-...` domain. This is the profile `CreateSpace` uses in `ownership_settings`. It is normally created by the SMUS portal when a user opens the project, but a fresh Terraform-only deployment never touches the portal, so `infra/space.tofu` creates it with `aws_sagemaker_user_profile.deployer`.

The SageMaker user-profile name is the DataZone profile ID (a UUID); that is why the space owner, tags, and tracker all use the lookup value.

If a human logs into the portal **before** Terraform creates the project-domain profile, SMUS may create it first. The apply then fails with an "already exists" style error; adopt it once with `tofu import` (see [03-troubleshooting.md](03-troubleshooting.md)). The execution role on the Terraform-created profile is the project execution role; if the space starts but hits permission errors, compare it with the portal-created profile's role.

## The space provider bug and the tracker

`aws_sagemaker_space` in provider 6.73.0 does not mark `ownership_settings` or `space_sharing_settings` as force-new, and its update path never sends them; the `UpdateSpace` API does not accept them either. An in-place update is therefore silently ignored and the next plan repeats the diff.

`infra/space.tofu` handles this with:

- `terraform_data.space_identity`, whose `triggers_replace` contains the DataZone profile ID and `"Private"`.
- `lifecycle { replace_triggered_by = [terraform_data.space_identity] }` on the space.

If either value changes, the tracker is replaced, which forces the space through `CreateSpace` instead of `UpdateSpace`. Keep this. If you ever need to force it manually:

```bash
tofu -chdir=infra/ apply -replace='aws_sagemaker_space.user'
```

Do not remove the tracker because a plan happens to look clean today.

## Space tags and the managed policy conditions

`SageMakerStudioUserIAMDefaultExecutionPolicy` allows `sagemaker:UpdateSpace`, `CreateApp`, and `DeleteApp` only for private spaces whose `AmazonDataZoneUser` tag equals the caller's `datazone:userId`. `infra/space.tofu` therefore sets:

- `ownership_settings.owner_user_profile_name` to the DataZone profile ID,
- `space_sharing_settings.sharing_type = "Private"`,
- tags `AmazonDataZoneUser`, `AmazonDataZoneProject`, and `AmazonDataZoneDomain`.

The `aws_sagemaker_user_profile` carries the same tags. Removing any of these produces "no identity-based policy allows `sagemaker:UpdateSpace`" when the portal starts the space, even though the space exists.

## GPU image and quota

- `var.space_instance_type` defaults to `ml.g4dn.xlarge`.
- `var.space_image_arn` is the **GPU** SageMaker Distribution image, not the CPU one. The default ARN is region-specific (`ap-southeast-1`). Omitting it gives a GPU instance with a CPU image: `nvidia-smi` is missing and `torch.cuda.is_available()` is false.
- The `Studio JupyterLab Apps running on ml.g4dn.xlarge instances` quota must be at least 1. The quota is per account and region; [README.md](../../README.md) records the tested code `L-39F81BFB` and an example ARN. A quota of 0 does not block `tofu apply`; it blocks **starting** the space.
- Changing `var.region` requires changing `space_image_arn` to that region's GPU image ARN and requesting the quota in the new region.

## Domain IDs are different

- `dzd-...` is the SageMaker Unified Studio/DataZone domain.
- `d-...` is the per-project SageMaker AI domain.

The project-domain lookup lists SageMaker domains and matches the project ID in `DomainName`. Do not point `aws_sagemaker_space.domain_id` at `module.sagemaker_unified_studio.domain_id`; the `CreateSpace` API expects the per-project `d-...` domain.

## Project membership and ownership

`module.project_membership` is intentionally configured with `project_owners = {}`. The project creator is auto-added as `PROJECT_OWNER` by DataZone. Adding the deployer as an explicit member races that auto-membership and produces `User is already in the project`. Leaving the module empty is deliberate.

## Destroy quirks

- Stop `${var.name_prefix}-gpu-space` before destroying. A running space blocks cleanup.
- Empty the module's tooling S3 bucket first; its `force_destroy` is disabled.
- The project module's destroy path uses the AWS CLI to delete project environments, so AWS CLI v2 must be available on the destroy host.
- DataZone user-profile deletion is a no-op in the provider; do not expect `tofu destroy` to remove a profile independently. Profiles disappear with their domain.
- Domain and project deletion are asynchronous; destroy can take 15–30 minutes.

## State, credentials, and scope

- Local state only. Never commit `infra/terraform.tfstate` or `.terraform/`; commit `infra/.terraform.lock.hcl`.
- The demo attaches AWS managed execution policies and expects broad IAM permissions. Treat it as a demo account stack, not a production pattern.
- The `external` lookups use the AWS CLI's credential chain. Keep the CLI and the `aws` provider in the same account and region; an assumed-role provider configuration that the CLI does not share will time out.

## README relationship

[README.md](../../README.md) is the tested human happy path: the five commands, the quota caveat, teardown, and screenshots. This document records the traps that the README intentionally omits. If they ever disagree, the five commands in [README.md](../../README.md) are canonical; treat a disagreement as documentation drift and report it rather than "fixing" the infrastructure.
