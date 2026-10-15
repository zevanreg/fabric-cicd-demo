#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository="$(terraform -chdir="$script_dir" output -raw github_repository)"
resource_group="$(terraform -chdir="$script_dir" output -raw runner_resource_group_name)"
vm_name="$(terraform -chdir="$script_dir" output -raw runner_vm_name)"
runner_name="${vm_name}-$(date +%s)"
registration_token="$(gh api --method POST "repos/$repository/actions/runners/registration-token" --jq .token)"
token_base64="$(printf '%s' "$registration_token" | base64 | tr -d '\n')"
registration_token=

run_command="$(mktemp)"
trap 'rm -f "$run_command"' EXIT
chmod 600 "$run_command"

cat > "$run_command" <<EOF
\$ErrorActionPreference = "Stop"
Set-Location "C:\actions-runner"
if (Test-Path ".runner") {
  Get-Service -Name "actions.runner.*"
  exit 0
}
\$token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$token_base64"))
\$configArguments = @(
  "--unattended",
  "--url", "https://github.com/$repository",
  "--token", "\$token",
  "--name", "$runner_name",
  "--labels", "fabric-infra",
  "--work", "_work",
  "--runasservice",
  "--windowslogonaccount", "NT AUTHORITY\NETWORK SERVICE",
  "--windowslogonpassword", "unused",
  "--replace"
)
& ".\config.cmd" @configArguments
if (\$LASTEXITCODE -ne 0) {
  throw "Runner configuration failed with exit code \$LASTEXITCODE."
}
\$token = \$null
Get-Service -Name "actions.runner.*" | Start-Service
Get-Service -Name "actions.runner.*"
EOF

az vm run-command invoke \
  --resource-group "$resource_group" \
  --name "$vm_name" \
  --command-id RunPowerShellScript \
  --scripts @"$run_command" \
  --output table

gh api "repos/$repository/actions/runners" \
  --jq ".runners[] | select(.name == \"$runner_name\") | {name, status, labels: [.labels[].name]}"
