# Environment and dependencies

Read this before running any OpenTofu command. The deployment assumes a full AWS account and a Linux-like shell; it is not a local-only demo.

## Tested environment

| Component | Tested value | Notes |
| --- | --- | --- |
| OS | Linux x86_64 (Ubuntu-family) | Bash 5.3.9. No GUI requirement. |
| OpenTofu | 1.13.9 | The local state was written by this version. |
| AWS CLI | 2.40.3 | AWS CLI v2 is required; v1 is untested and may lack DataZone commands. |
| Bash | 5.3.9 | The `external` data sources execute `bash -c` scripts. |
| Git | Required | Needed by `tofu init` to clone the Git-pinned module. Not necessarily on an agent sandbox's `PATH`. |
| AWS provider | 6.73.0 | Locked; module requires `>= 6.51.0`. |
| AWSCC provider | 1.110.0 | Transitive requirement of the AWS-IA module (`>= 1.89.0`). |
| External provider | 2.4.2 | Runs the DataZone/SageMaker lookups. |
| Random provider | 3.9.1 | Transitive module requirement. |
| Time provider | 0.14.2 | Used by the project role wait. |

## Operating-system support

- **Linux x86_64**: supported and tested. This is the reference environment.
- **Windows**: use **WSL2** with a Linux distribution. Native PowerShell/`cmd.exe` is not supported: the configuration runs `bash -c`, uses `seq`, `printf`, and POSIX heredocs. Git Bash is untested.
- **macOS**: untested. Bash is available, but stock macOS does not ship GNU `seq`, which the `external` lookups use. Install GNU coreutils (`brew install coreutils`, then put its `gnubin` directory on `PATH`) or run the stack from a Linux container/WSL2. Expect no support beyond that.

## Software dependency details

| Dependency | Minimum / tested | Why it is needed |
| --- | --- | --- |
| OpenTofu | `>= 1.8` for `.tofu` files; 1.13.9 tested | Parses `infra/*.tofu` and installs providers/modules. The AWS-IA module itself declares `>= 1.7`. |
| AWS CLI v2 | 2.40.3 tested | `external` data sources call `aws datazone get-user-profile` and `aws sagemaker list-domains`; diagnostics also use `aws sagemaker list-user-profiles`. The project module's destroy path shells out to `aws`. |
| Git | Any recent version | `source = "git::https://github.com/..."` in `studio.tofu` and `project.tofu`; `tofu init` clones the pinned commit. If the module cache is already populated, a fresh clone may not be needed, but do not delete `.terraform/` unless Git is available. |
| Bash + GNU coreutils | Bash 4+ practical; `seq` required | The lookups use `set -euo pipefail`, `for _ in $(seq 1 60)`, and `printf`. |
| Network access | At init and apply | `init` reaches `registry.opentofu.org` and GitHub. Apply reaches AWS APIs. |

`jq` and Python are **not** required by the configuration. The scripts use the AWS CLI's built-in `--query` (JMESPath) instead.

## AWS prerequisites

- **Account**: a non-production AWS account is strongly recommended. The stack creates VPC resources, IAM roles and policies, S3, DataZone, and SageMaker resources, and attaches AWS managed admin-style execution policies for the demo. Do not run it in a shared production account.
- **Credentials**: the caller needs broad permissions across EC2/VPC, IAM, S3, DataZone, SageMaker, CloudFormation (for `awscc`), and read-only Service Quotas. The exact least-privilege policy is not provided; an admin role is the expected demo setup.
- **Region**: the default is `ap-southeast-1`. It must be a [supported SageMaker Unified Studio region](https://docs.aws.amazon.com/sagemaker-unified-studio/latest/adminguide/supported-regions.html). Changing `var.region` is not a one-line change: the GPU image ARN (`var.space_image_arn`) is region-specific, and the GPU quota is per region.
- **GPU quota**: `Studio JupyterLab Apps running on ml.g4dn.xlarge instances` must be above 0. The quota code is `L-39F81BFB`. It is per account and per region. The ARN printed in [README.md](../../README.md) is specific to the author's account/region; do not reuse that ARN in another account.
- **CLI/provider alignment**: the `external` data sources run the AWS CLI with its own credential chain. Do not configure the `aws` provider with an `assume_role` that the CLI does not also use, and keep `AWS_PROFILE`, `AWS_REGION`, and the provider region consistent. Mismatches show up as lookup timeouts or "not found" errors.
- **Service Quotas read access** is useful for preflight checks; the quota increase itself is requested by a human in the Service Quotas console or with `aws service-quotas request-service-quota-increase`.

## Region, IDs, and naming

- `dzd-...` is the SageMaker Unified Studio / DataZone domain created by `module.sagemaker_unified_studio`.
- `d-...` is the per-project SageMaker AI domain created asynchronously for the project. It is **not** the same ID as `dzd-...`.
- The project's SageMaker domain is found by listing SageMaker domains and matching the project ID in the domain name.
- The space name is `${var.name_prefix}-gpu-space`; the default project name is `${var.name_prefix}-project`; the domain name is `${var.name_prefix}-unified-studio-domain`.

## State and backend

- The stack uses the **local backend**: `infra/terraform.tfstate`. There is no S3/DynamoDB backend and no state locking beyond OpenTofu's local lock file.
- Never commit `terraform.tfstate` or `.terraform/`; both are ignored by `.gitignore`. Do commit `infra/.terraform.lock.hcl`.
- Run only one apply/destroy at a time from one machine. If the state is lost, do not destroy/recreate blindly; adopt resources with `tofu import` (see [03-troubleshooting.md](03-troubleshooting.md)).
- The module cache under `infra/.terraform/modules/` is disposable but is also the only local copy of the pinned GitHub module. Deleting it requires a working `git` and network access.

## Timing and cost expectations

- `tofu init`: usually 1–3 minutes.
- First apply phase (network plus the domain-independent project execution role): roughly 5–10 minutes (NAT gateway and route tables).
- Second apply phase (domain, project, profiles, space): commonly 20–40 minutes. The `external` lookups poll up to 15 minutes for the project's SageMaker domain and up to 10 minutes for the DataZone profile.
- Starting the GPU space adds a few minutes and begins GPU billing. Stop the space when it is not in use.
- `tofu destroy` can take 15–30 minutes and requires an empty tooling bucket; see [04-verification.md](04-verification.md).

## Preflight commands

```bash
tofu version
aws --version
git --version
bash --version
seq 1 1
aws sts get-caller-identity
aws service-quotas get-service-quota \
  --service-code sagemaker \
  --quota-code L-39F81BFB \
  --region ap-southeast-1 \
  --query 'Quota.{Name:QuotaName,Value:Value,Adjustable:Adjustable}'
```

Expected: OpenTofu 1.13.x, AWS CLI 2.x, a Git version, Bash 4+/5.x, a successful identity, and a quota value of at least 1 (a value of 0 is the common blocker; see [03-troubleshooting.md](03-troubleshooting.md)).

## Agent-sandbox notes

Some agent sandboxes do not expose `tofu` or `git` on `PATH` even though the project was previously applied from the host shell. Verify both before `init`; do not delete `infra/.terraform/` or the state when a tool is missing. The local state references the pinned module and providers; the lock file records the exact versions above.
