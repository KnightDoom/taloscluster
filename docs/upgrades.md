# Talos and Kubernetes upgrades

Run repository commands through `mise exec --`. Upgrades are operator actions;
merging a version change does not upgrade Talos or Kubernetes through Flux.

## Choose and record a target

1. Check live versions with `mise exec -- kubectl get nodes -o wide`.
2. Read the target release notes and the Talos support matrix. Choose compatible
   Talos and Kubernetes versions, and check Cilium, Longhorn, and GPU driver
   compatibility. Upgrade Talos through adjacent minor releases, using the latest
   patch of each intermediate minor. Upgrade Kubernetes one minor at a time.
   Choose the order from the support matrix; do not assume Talos must always go first.
3. Change the appropriate version in
   `bootstrap/templates/kubernetes/bootstrap/talos/talconfig.yaml.j2`.
   These versions currently live in the template, not `config.yaml`.
4. The user runs `mise exec -- task configure -y`. Review the generated
   `kubernetes/bootstrap/talos/talconfig.yaml` and the diff, then commit the
   intended target. Keep Talos and Kubernetes upgrades as separate operations.

Do not apply every generated machine configuration as a substitute for upgrading.
Changing the version in a file alone does not upgrade the running cluster.

## Before each operation

The cluster has one control-plane node (`talos0`, `192.168.86.26`). Its reboot
interrupts the Kubernetes API; there is no redundant control plane.

```sh
mise exec -- kubectl get nodes -o wide
mise exec -- kubectl get pods -A
mise exec -- kubectl get pdb -A
mise exec -- talosctl --nodes 192.168.86.26 health --wait-timeout=10m
```

Resolve unhealthy infrastructure, blocked disruption budgets, and degraded
storage before proceeding. Confirm workload backups separately from etcd:
an etcd snapshot does not contain persistent volume contents.

Take an etcd snapshot to a unique path outside the repository. For example, after
creating a private backup directory, replace the path below with a new filename:

```sh
mise exec -- talosctl --nodes 192.168.86.26 etcd snapshot /absolute/private/backup/path/etcd-before-upgrade.snapshot
```

Treat snapshots as secrets. Keep a protected off-cluster copy, together with the
Talos secrets, configuration, and a tested recovery procedure.

## Talos

The existing task upgrades one node using its live Image Factory schematic and
Secure Boot state, with the target version read from rendered `talconfig.yaml`.
Check that these live schematics match the intended hardware extensions in source.
Upgrade one node at a time and verify it before continuing. Start with a worker
as a canary, then the other worker, then the controller during a maintenance window.

```sh
mise exec -- task talos:upgrade-node HOSTNAME=talos1
mise exec -- kubectl get nodes -o wide
# After checking workloads, storage, networking, and GPU workloads:
mise exec -- task talos:upgrade-node HOSTNAME=talos2
# After verification, during the control-plane maintenance window:
mise exec -- task talos:upgrade-node HOSTNAME=talos0
```

The current task suspends ALL Flux Kustomizations and resumes ALL on success.
Record which were already suspended before using it:

```sh
mise exec -- flux get kustomizations -A
```

If the task fails, it can leave reconciliation suspended. Inspect the node and
Flux state before recovering. Resume only Kustomizations suspended for this
operation, preserving intentionally suspended resources:

```sh
mise exec -- flux --namespace flux-system resume kustomization <name>
```

The task's successful resume-all also resumes intentionally suspended resources;
restore those to their prior state. This task should gain state-preserving cleanup
before being used for unattended upgrades.

## Kubernetes

Preview the cluster-wide operation using the explicit control-plane address and
the target version from rendered `talconfig.yaml`:

```sh
mise exec -- talosctl --nodes 192.168.86.26 upgrade-k8s --to <target-version> --dry-run
```

Review bootstrap manifest changes, particularly resources managed by Flux such
as CoreDNS and Cilium's kube-proxy replacement. Then run:

```sh
mise exec -- task talos:upgrade-k8s
```

`upgrade-k8s` upgrades the whole cluster, even though the API call goes to one
control-plane node. An interrupted operation can be rerun to continue. Do not
treat a Kubernetes downgrade as the recovery plan.

## Verify and recover

Check all node versions and readiness, Talos health, Flux reconciliation, DNS,
ingress, storage health, and GPU workloads. Generate updated local machine
configuration when needed with `mise exec -- task talos:generate-config`; inspect
configuration changes before applying them to upgraded nodes.

If Talos fails to boot, its A/B boot mechanism supports rollback. For a reachable
node, consult `talosctl rollback --help` and the release-specific rollback notes
before acting. Stop the rollout at the first failure. For control-plane data loss,
use the documented etcd disaster recovery process and the protected snapshot.

References:

- [Talos upgrades](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
- [Kubernetes upgrades](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/upgrading-kubernetes)
- [Talos support matrix](https://docs.siderolabs.com/talos/v1.13/getting-started/support-matrix)
