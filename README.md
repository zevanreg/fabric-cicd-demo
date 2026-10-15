# Fabric CI/CD demo

This repository is a monorepo for Azure/Fabric infrastructure and two workload
deployment examples:

| Path | Purpose |
| --- | --- |
| `infra/bootstrap/` | Creates the deployment identity, GitHub OIDC trust, private Terraform state storage, and self-hosted infrastructure runner. |
| `infra/terraform/` | Creates the Fabric capacity and one Fabric workspace per configured environment. |
| `src/inline-workloads/` | Deploys the inline notebook workload. |
| `src/wheel-workloads/` | Deploys the wheel-based workload and its Fabric environment. |

## Prerequisites

- Terraform 1.8 or later and Azure CLI.
- GitHub CLI authenticated as a repository administrator.
- An Azure subscription where the bootstrap operator can create a resource
  group and storage account, assign Azure roles at subscription scope, and
  register resource providers.
- Entra permissions for the bootstrap operator to create an app registration,
  service principal, and federated identity credentials (for example,
  Application Administrator), plus permission to make the required Azure role
  assignments (for example, Role Based Access Control Administrator).
- A Fabric administrator identity that can configure tenant settings. It is
  separate from the shared workload deployment identity.
- The following Fabric tenant settings enabled for a security group containing
  the deployment service principal:
  - **Service principals can call Fabric public APIs**.
  - **Service principals can create workspaces, connections, and deployment
    pipelines**. This setting is disabled by default for new tenants.
  Configure both under **OneLake catalog > Govern > Configurations > Tenant
  settings** in the Fabric portal.
- A GitHub repository owner who can configure environments, variables, and
  secrets.

The shared deployment application receives subscription-level Contributor and
state-storage Blob Data Contributor access. Any trusted GitHub OIDC subject can
therefore use those permissions; federation restricts token issuance but does
not isolate Azure RBAC permissions. Protect the `dev`, `test`, and `prod`
GitHub environments with suitable branch restrictions and approval rules, and
protect the `main` branch used for infrastructure deployment.

The Terraform state account disables public network access. Its blob endpoint
is reachable only through a private endpoint in the bootstrap VNet. A private
Windows Server VM runs infrastructure deployments, resolves the endpoint through an
Azure Private DNS zone, and uses a NAT Gateway for outbound GitHub, Azure, and
package access. The VM has no public IP and its NSG denies all inbound traffic.
Shared-key access and public blob access are also disabled.

## 1. Bootstrap Azure identity and remote state

Bootstrap state is local because it creates the storage account used by the
main Terraform backend. Back up `infra/bootstrap/terraform.tfstate` and its
backup securely outside Git. Do not lose this state or run competing bootstrap
applies.

Sign in with the authorized bootstrap operator, copy the example file, and
provide your Azure subscription and a globally unique storage account name
(3-24 lowercase letters and digits):

```bash
az login --tenant YOUR_TENANT_ID
az account set --subscription YOUR_SUBSCRIPTION_ID
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.Compute --wait
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
```

Edit `infra/bootstrap/terraform.tfvars`:

- `subscription_id`: subscription where the state storage account and workload
  identity permissions will be created.
- `storage_account_name`: globally unique lowercase name.
- `resource_group_name` and `location`: location for the separate Terraform
  state resource group.
- `github_repository`: this monorepo in `OWNER/REPOSITORY` form. The example
  uses `zevanreg/fabric-cicd-demo`; change it if your GitHub owner or repository
  differs.
- `github_owner_id`: immutable numeric ID of the GitHub organization or user
  that owns the repository.
- `github_repository_id`: immutable numeric repository ID. Find both IDs in
  the GitHub API or the repository's OIDC configuration.
- `deployment_application_display_name`: optional Entra application display
  name.
- `virtual_network_address_space`, `runner_subnet_address_prefix`, and
  `private_endpoint_subnet_address_prefix`: change these if the defaults overlap
  networks that will be peered later.
- `runner_vm_name` and `runner_vm_size`: optional runner VM settings. The
  default `Standard_D2s_v5` provides 2 vCPUs and 8 GiB for Windows and Terraform.
- `environments`: Fabric workspace keys. The default provisions `developer1`,
  `dev`, `test`, and `prod`.
- `github_environments`: workspace environments allowed to run CI/CD workflows.
  The default is `dev`, `test`, and `prod`; `developer1` is provisioned only as
  a developer workspace.

Use the GitHub CLI to retrieve the immutable numeric IDs:

```bash
gh auth login
gh api orgs/OWNER --jq '.id'
gh api repos/OWNER/REPOSITORY --jq '.id'
```

For a user-owned repository, replace the organization query with:

```bash
gh api users/OWNER --jq '.id'
```

Set the returned decimal values as `github_owner_id` and
`github_repository_id`. Use the numeric `id` values, not the GraphQL `node_id`
strings.

Run bootstrap from the repository root:

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output -raw backend_config \
  > infra/terraform/backend.hcl
terraform -chdir=infra/bootstrap output -raw deployment_config \
  > infra/terraform/deployment.auto.tfvars.json
```

Bootstrap creates the state container through Azure Resource Manager rather
than the storage data plane. This allows the initial apply to run from an
operator workstation even though storage public network access is disabled.
For an existing bootstrap state, the `removed` block intentionally forgets the
old AzureRM container resource without deleting the container; AzAPI then
adopts it through an idempotent ARM PUT.

The generated handoff files, Terraform state, plans, and tfvars are ignored by
Git. Bootstrap creates environment-scoped OIDC credentials for the configured
`github_environments`, a main-branch credential for infrastructure deployment,
and the deployment application's Azure access. GitHub environments themselves
are configured in the next section; bootstrap does not create them.

The Windows administrator password is generated automatically and retained
only in the sensitive local bootstrap state. It is not an input or output.
There is no SSH key, public IP, RDP rule, or other inbound access. Use Azure Run
Command for management; Azure can reset the administrator password if recovery
is ever required.

### Register the self-hosted runner

The bootstrap apply waits for the VM extension to install Azure CLI and the
checksum-verified Windows runner package. Register the prepared VM:

```bash
infra/bootstrap/register-runner.sh
```

The registration helper obtains a one-hour, one-time runner token with `gh`,
sends it through Windows Azure Run Command, starts the runner as a Windows
service under `NT AUTHORITY\NETWORK SERVICE`, and does not put the token in
Terraform configuration or state. It is idempotent when the VM is already
configured. The runner receives the `fabric-infra` label required by the
infrastructure deployment workflow.

Confirm that the runner is online under **Settings → Actions → Runners** before
dispatching infrastructure deployment. Repository-level self-hosted runners
should be used only with trusted workflows. Keep branch protection on `main`;
pull-request CI continues to use GitHub-hosted runners and cannot target this
VM.

If resources are already managed by an earlier Terraform state, do not apply
these configurations as a fresh deployment. Back up the existing states and
transfer/import ownership before applying to avoid Terraform replacing an
existing application or Fabric resources.

## 2. Configure infrastructure deployment

In **Settings → Environments**, create one GitHub environment for every entry
in the bootstrap `github_environments` variable. The defaults are `dev`, `test`,
and `prod`. Add the appropriate protection rules, especially for `test` and
`prod`. Do not create a `developer1` GitHub environment; Terraform provisions
that workspace for direct developer use only.

Add these **repository variables** for the infrastructure deployment workflow:

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | Bootstrap output `deployment_application_client_id`. |
| `AZURE_TENANT_ID` | Azure tenant ID used for bootstrap. |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID used for bootstrap and the Fabric capacity. |
| `AZURE_CLIENT_OBJECT_ID` | Bootstrap output `deployment_service_principal_object_id`. |
| `TFSTATE_RESOURCE_GROUP` | Bootstrap state resource group name. |
| `TFSTATE_STORAGE_ACCOUNT` | Bootstrap state storage account name. |
| `FABRIC_CAPACITY_ADMINS` | Non-empty JSON array of additional Fabric administrator UPNs or service principal object IDs, for example `["admin@example.com"]`. The deployment service principal is always included so the workflow can discover and manage the capacity. |

The deployment workflows read these shared identifiers using `vars.*`; they do
not need an Azure client secret. Workload workflows use immutable environment
subjects of the form
`repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:ENVIRONMENT`.
Infrastructure deployment uses
`repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:ref:refs/heads/main` and does not
use a GitHub environment. The owner, repository, IDs, environment names, and
branch must exactly match the bootstrap settings.

Infrastructure CI is validation-only, requires no GitHub secrets or Azure
credentials, and never applies Terraform.

## 3. Deploy Fabric infrastructure

Deploy the main Fabric infrastructure only through the `Deploy infrastructure`
GitHub Actions workflow. Do not run the main Terraform configuration locally.
The workflow uses the bootstrapped OIDC identity on the `fabric-infra`
self-hosted runner, verifies that the state hostname resolves to a private IP,
initializes the remote backend, and serializes runs against the shared state.

1. Open **Actions → Deploy infrastructure → Run workflow** and select the
   `main` branch.
2. Select `plan` and review the complete Terraform plan.
3. Run the workflow again from `main` with `apply`. The apply run creates a fresh plan and
   applies that exact saved plan.
4. Copy the environment-to-workspace ID map from the run summary.

The main configuration uses the OIDC deployment identity for Azure and Fabric
management. Fabric automatically grants the shared deployment application
Admin on each workspace it creates; Terraform does not add a duplicate role
assignment. The workload workflows reuse that identity for publishing.

Creating a Fabric capacity can incur charges. Obtain approval first, and pause
the capacity when not in use. Keep both Terraform states safe; do not delete
bootstrap storage while the main infrastructure state is in use.

### Configure workload deployment

After infrastructure deployment succeeds, use the generated workspace ID map
from the apply run summary to add `FABRIC_WORKSPACE_ID` to each CI/CD GitHub
environment. The `developer1` workspace does not need this variable:

| Environment variable | Value |
| --- | --- |
| `FABRIC_WORKSPACE_ID` | The workspace ID for that environment from `terraform output workspace_ids`. |

Configure the following **repository secrets** for wheel workflows:

| Secret | Required? | Purpose |
| --- | --- | --- |
| `PIN_PR_TOKEN` | Required to run `wheel-update-pin`. | Fine-grained token for this repository with Contents and Pull requests write access. The workflow uses it to update `release.json` on `dev` and open or update a pin-only PR. |
| `GH_RELEASE_TOKEN` | Optional for public releases; needed when release access requires authentication or to use a dedicated token. | Contents read access to the repository named in `src/wheel-workloads/release.json`. Used to look up and download the pinned published wheel. Without it, workflows fall back to `GITHUB_TOKEN`. |

Inline workload deployment does not require additional repository secrets.

## 4. Workload CI and deployment

The existing workflows are under `.github/workflows/`:

- `inline-ci.yml` runs inline unit tests on pull requests and pushes to `dev`
  when `src/inline-workloads/**` or an inline workflow changes.
- `wheel-ci.yml` runs wheel unit tests on pull requests and pushes to `dev`
  when `src/wheel-workloads/**` or a wheel workflow changes.
- `inline-promote.yml` and `wheel-promote.yml` run on matching workload changes
  merged to `main`. Each deploys to `test`, then deploys to `prod` only if the
  test deployment succeeds.
- `inline-deploy.yml` and `wheel-deploy.yml` can also be run manually from
  **Actions → Run workflow**, selecting `dev`, `test`, or `prod`. The wheel
  workflow also lets you select `all` or `environment` scope.
- `infra-deploy.yml` is manual and runs against the protected `prod`
  environment. Select `plan` to preview changes or `apply` to create a fresh
  plan and apply it. Infrastructure runs are serialized to protect the shared
  Terraform state.
- `wheel-update-pin.yml` is a manual workflow dispatched from `main`. Supply a
  published stable library release tag (for example, `v1.2.3`). It verifies the
  release and wheel checksum, updates the pin on `dev`, and opens or updates a
  pull request. It requires `PIN_PR_TOKEN`.

The inline and wheel path filters are independent. A change under one workload
folder does not trigger the other workload's CI or promotion workflow.

## Infrastructure validation

The infrastructure workflow validates and tests both Terraform roots for pull
requests and pushes affecting `infra/**` or
`.github/workflows/infra-ci.yml`. It uses mocked providers and does not connect
to Azure or deploy resources. Run the same checks locally:

```bash
terraform -chdir=infra/bootstrap fmt -check -recursive
terraform -chdir=infra/bootstrap init -backend=false -input=false -lockfile=readonly
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap test
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false -input=false -lockfile=readonly
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform test
```

For component-specific details, see [inline workload documentation](src/inline-workloads/README.md)
and [wheel workload documentation](src/wheel-workloads/README.md).
