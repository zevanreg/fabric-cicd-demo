# Wheel workload

This workload publishes:

- `DateDemoEnvironment`, containing an immutable pinned `demo-date` wheel; and
- `PrintCurrentDateWheel`, which calls `demo_date.print_current_date()` and
  prints the current UTC date as `YYYY-MM-DD`.

The wheel is staged in the Environment's `Libraries/CustomLibraries` directory.
It is not committed to this repository and is not installed from a notebook
`%pip` cell. The notebook requires no Lakehouse.

See the [repository README](../../README.md) for infrastructure provisioning,
GitHub variables and secrets, environment protection, CI triggers, and
test-to-production promotion.

## Release pin

`release.json` is the deployment trust boundary. It records:

- the GitHub release repository and stable `vX.Y.Z` tag;
- the expected universal wheel asset name; and
- the independently reviewed SHA-256 digest.

Deployment accepts only a published, non-draft, non-prerelease release. It
verifies the release checksum, wheel digest, package name and version, pure
Python metadata, and `py3-none-any` tag before Azure authentication.

Do not replace the pin from an unreviewed download during deployment. Tags or
release assets can otherwise be replaced without a reviewed repository change.
The initial blank checksum intentionally blocks deployment until a real release
has been approved.

### Updating the pin

Run **Actions → Update wheel library release pin** from `main` with the published
release tag. The workflow verifies the release and opens or updates a pin-only
pull request against `main`. Review and merge that pull request normally.

The updater rejects downgrades and changed assets for an already pinned tag. It
does not auto-merge or deploy. Re-running an unchanged tag is a no-op.

## Local offline validation

From `src/wheel-workloads`, with a trusted wheel available locally:

```bash
python3.11 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python scripts/deploy.py \
  --stage dev \
  --workspace-id 11111111-1111-4111-8111-111111111111 \
  --wheel /path/to/demo_date-0.1.0-py3-none-any.whl \
  --sha256 APPROVED_64_CHARACTER_SHA256 \
  --dry-run
```

The sample workspace ID is only an offline target. Dry-run never obtains
credentials, constructs a `FabricWorkspace`, or calls Fabric. It validates and
stages the wheel without extracting it, copies definitions under the ignored
`.staging/` directory, and writes an ignored `deployment-manifest.json`.
Tracked sources are not modified.

Dependencies are pinned in `requirements.txt`. Use Python 3.11 and an approved
package index that exposes the pinned versions rather than silently upgrading
deployment dependencies.

## Deployment scopes

The deployment workflow supports two scopes:

| Scope | Behavior |
| --- | --- |
| `all` | Publishes the Environment and Notebook in dependency order. Use for initial deployment and notebook changes. |
| `environment` | Publishes only the Environment. Use for a library-only update after the notebook binding already exists. |

The committed `release.json` is always used. There is no separate workload SHA
input. Environment-only deployment does not republish the notebook, and existing
Spark sessions can retain the old library until restarted.

The deployment manifest records the workload commit, stage, workspace, scope,
wheel version and digest, timestamp, and final status. A failed publish can
leave partial cloud changes and is not automatically rolled back.

## Live verification and rollback

After deployment:

1. Open `PrintCurrentDateWheel` in the target workspace.
2. Confirm it is bound to `DateDemoEnvironment`.
3. Start a new Spark session.
4. Run the notebook and confirm it prints one UTC date.

The workflow publishes definitions but does not execute the notebook. Roll back
by reverting both workload definitions and `release.json` to a previously
approved revision, then deploy through the normal branch and environment
promotion flow. Use `all` when notebook definitions or bindings must also be
restored.

For import failures, confirm that Environment publication completed, the
notebook binding targets the correct workspace, and a new Spark session was
started. For authorization failures, verify the Fabric tenant
service-principal setting, workspace role, active capacity, and the
environment's `FABRIC_WORKSPACE_ID`.

References:

- [fabric-cicd parameterization](https://microsoft.github.io/fabric-cicd/latest/how_to/parameterization/)
- [Fabric Environment publish API](https://learn.microsoft.com/en-us/rest/api/fabric/environment/items/publish-environment)
