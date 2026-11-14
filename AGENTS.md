# AGENTS.md

Agent entry point for deploying the SageMaker Unified Studio demo with OpenTofu. Humans should start with [README.md](README.md); agents should read the documents below in order.

## Read first

- [README.md](README.md) — tested human procedure, quota caveat, teardown, screenshots.
- [Environment and dependencies](docs/agents/00-environment.md)
- [Bootstrap](docs/agents/01-bootstrap.md)
- [Quirks and invariants](docs/agents/02-quirks.md)
- [Troubleshooting](docs/agents/03-troubleshooting.md)
- [Verification](docs/agents/04-verification.md)

## Minimum toolchain

- Linux x86_64 (tested) or WSL2 on Windows; macOS is untested and needs GNU `seq`.
- OpenTofu 1.13.9 tested (minimum 1.8 for `.tofu` files; the module requires >= 1.7).
- AWS CLI v2 (2.40.3 tested); v1 is not supported by this project's `external` lookups.
- Git, bash, and GNU `seq` on `PATH`.
- AWS credentials with broad IAM, DataZone, SageMaker, and S3 permissions.
- Region `ap-southeast-1`, or another supported SageMaker Unified Studio region.
- GPU quota `L-39F81BFB` above 0 in that region.

## Canonical bootstrap

```bash
tofu -chdir=infra/ init
tofu -chdir=infra/ plan -exclude=module.sagemaker_unified_studio
tofu -chdir=infra/ apply -exclude=module.sagemaker_unified_studio
tofu -chdir=infra/ plan
tofu -chdir=infra/ apply
```

The first phase exists because the AWS-IA module validates subnet IDs in a `for_each` that is unknown while the VPC is created in the same apply. It is a no-op on existing state. Do not remove it.

## Non-negotiables

- Never edit or commit `infra/terraform.tfstate`; state is local and gitignored.
- Never re-add an `aws_datazone_user_profile` resource; the module's model-governance project auto-creates the DataZone profile.
- Keep `terraform_data.space_identity`, the `AmazonDataZoneUser` tags, and Private space sharing.
- Do not change the pinned module commit, region, or GPU image ARN independently.
- Keep AWS CLI credentials and region aligned with the provider; `external` data sources call `aws`.
- Stop the space and empty the tooling bucket before `tofu destroy`.
- Fix drift with `tofu import` or a targeted replacement; never destroy the stack to clear one object.

## Docs index

| Document | Read when |
| --- | --- |
| [00-environment.md](docs/agents/00-environment.md) | Before running anything; toolchain, permissions, quota, state. |
| [01-bootstrap.md](docs/agents/01-bootstrap.md) | First or fresh deploy; step-by-step expectations. |
| [02-quirks.md](docs/agents/02-quirks.md) | Changing the config; understanding why the procedure has its shape. |
| [03-troubleshooting.md](docs/agents/03-troubleshooting.md) | Any apply, start, or destroy failure; imports and diagnostics. |
| [04-verification.md](docs/agents/04-verification.md) | After apply and before teardown. |

Stop and ask the human if the quota is 0 and cannot be raised, IAM permissions are missing, state is inconsistent, or a fix would be destructive.
