# Inline workload

This workload publishes the `PrintCurrentDateInline` Fabric notebook. The
notebook uses only Python's standard library:

```python
from datetime import datetime, timezone
print(datetime.now(timezone.utc).isoformat(timespec="seconds"))
```

It has no custom Fabric Environment, wheel, Lakehouse, or notebook `%pip`
dependency. Python 3.11 is used for CI and deployment tooling; it does not
select a custom Fabric runtime.

See the [repository README](../../README.md) for infrastructure provisioning,
GitHub variables, environment protection, CI triggers, and promotion flow.

## Local offline validation

From `src/inline-workloads`:

```bash
python3.11 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python scripts/deploy.py \
  --stage dev \
  --workspace-id 11111111-1111-4111-8111-111111111111 \
  --dry-run
```

The sample workspace ID is only an offline target. Dry-run does not obtain
credentials, construct a `FabricWorkspace`, or call Fabric APIs. It stages a
copy of `workspace/` under the ignored `.staging/` directory and writes an
ignored `deployment-manifest.json`; tracked sources are not modified.

Dependencies are pinned in `requirements.txt`. Use Python 3.11 and an approved
package index that exposes the pinned versions rather than silently upgrading
deployment dependencies.

## Deployment behavior

The deployment script:

1. Validates the selected stage and workspace ID.
2. Copies the tracked Fabric definitions into a temporary staging directory.
3. Runs an offline preview before workflow authentication.
4. Publishes only `Notebook` items with `fabric-cicd`.
5. Records the commit, stage, workspace, timestamp, scope, and final status in
   `deployment-manifest.json`.

The publisher updates matching notebook definitions and does not remove orphaned
items. A failed publish can leave partial cloud changes; it is not automatically
rolled back.

## Live verification and rollback

After deployment, open `PrintCurrentDateInline` in the target workspace and
confirm that:

- it has no custom Environment or Lakehouse dependency;
- it prints one ISO 8601 UTC timestamp; and
- it runs successfully on the active Fabric capacity.

The workflow publishes definitions but does not execute the notebook. Roll back
by reverting to a previously approved workload revision and deploying that
revision through the normal branch and environment promotion flow.

For authorization failures, verify the Fabric tenant service-principal setting,
the target workspace role, active capacity, and the environment's
`FABRIC_WORKSPACE_ID`.

References: [fabric-cicd](https://microsoft.github.io/fabric-cicd/latest/).
