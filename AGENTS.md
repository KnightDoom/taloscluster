# AGENTS.md

## Repository Purpose

This repository manages a Talos Linux Kubernetes cluster with Flux. It is designed so the cluster can be re-rendered, scrapped, and bootstrapped again from templated source files.

## Core Workflow

- Treat `config.yaml` as the primary cluster input.
- Treat `bootstrap/templates/kubernetes/**` and `bootstrap/overrides/**` as the source templates.
- Treat `kubernetes/**` as generated output from the templates.
- For Kubernetes app changes, edit the matching file under `bootstrap/templates/kubernetes/apps/**` first. If updates are made to `kubernetes/apps/**`, ensure they are matched similarly in the corresponding template files in `bootstrap/templates/kubernetes/apps/**` (which will have a `.j2` suffix and be in jinja syntax).
- Run `task configure -y` after template edits. This renders templates with `makejinja`, encrypts `*.sops.*` files when needed, and validates manifests with kubeconform.
- Generated files in `kubernetes/apps/**`, `kubernetes/flux/**`, and `kubernetes/bootstrap/**` may be overwritten by `task configure -y`.
- Do not run 'task configure -y' unless explicitly asked. This is a user action unless mentioned in the prompt.

## Rendering Flow

- `Taskfile.yaml` task `configure` runs `bootstrap:template`, `bootstrap:secrets`, and `kubernetes:kubeconform`.
- `bootstrap:template` runs `makejinja` using `makejinja.toml`.
- `makejinja.toml` reads data from `config.yaml`, uses inputs from `bootstrap/overrides` and `bootstrap/templates`, writes output to the repository root, strips the `.j2` suffix, and uses custom delimiters.
- `bootstrap/scripts/plugin.py` registers helper filters/functions and calls `bootstrap/scripts/validation.py` before rendering.
- `.mjfilter.py` files conditionally include or exclude template directories based on `config.yaml` values.

## Template Syntax

- Jinja block delimiters are `#% ... %#`.
- Jinja variable delimiters are `#{ ... }#`.
- Jinja comment delimiters are `#| ... #|`.
- Keep rendered YAML valid after conditions are evaluated.
- Prefer existing helper functions and filters from `bootstrap/scripts/plugin.py` over ad hoc logic.

## Kubernetes App Layout

Use the existing Flux app structure when adding or changing apps:

```text
bootstrap/templates/kubernetes/apps/<namespace>/
  kustomization.yaml.j2
  namespace.yaml.j2
  <app>/
    ks.yaml.j2
    app/
      kustomization.yaml.j2
      helmrelease.yaml.j2
      secret.sops.yaml.j2        # when needed
      externalsecret.yaml.j2     # when needed
      kustomizeconfig.yaml.j2    # when needed
```

The generated equivalent lands under:

```text
kubernetes/apps/<namespace>/<app>/...
```

The namespace-level `kustomization.yaml.j2` should include `namespace.yaml` and each app `ks.yaml`. Each app `ks.yaml.j2` defines a Flux `Kustomization` in the `flux-system` namespace and points `spec.path` at `./kubernetes/apps/<namespace>/<app>/app`.

## YAML Style

- Start Kubernetes YAML documents with `---`.
- Use two-space indentation.
- Keep resource names lowercase and hyphenated.
- Use YAML anchors for repeated app names where the repo already does this, for example `name: &app radarr` and `app.kubernetes.io/name: *app`.
- Keep Flux intervals and timeouts consistent with nearby apps unless there is a reason to change them.
- Follow existing HelmRelease structure: `interval`, `chart`, `install.remediation`, `upgrade`, then `values` or `valuesFrom`.
- Keep commented optional blocks only when they are useful as local examples for future changes.

## Secrets

- Never write real secret material into non-SOPS files.
- Template secret manifests as `secret.sops.yaml.j2` when they must be generated.
- Let `task configure -y` and `bootstrap:secrets` handle SOPS encryption for generated `*.sops.*` files.
- Do not print or copy secret values from `config.yaml`, `age.key`, or generated SOPS files into chat or documentation.

## Validation

- After template changes, run `task configure -y` whenever practical.
- If only validating generated manifests, run `task kubernetes:kubeconform`.
- For live-cluster reconciliation, use `task kubernetes:reconcile` after committing and pushing changes.
- Do not hand-edit generated files as the only fix unless the user explicitly asks for a temporary generated-output patch.

## Operational Notes

- The current cluster config is a three-node Talos cluster on `192.168.86.0/24` with one controller and two workers.
- Node labels in `config.yaml` are used for hardware-specific scheduling, including Intel GPU generations.
- Talos and Flux bootstrap tasks live under `.taskfiles/bootstrap`, `.taskfiles/talos`, and `.taskfiles/kubernetes`.
- Preserve the repo's ability to rebuild the cluster from templates and `config.yaml`; avoid changes that only work in the already-rendered output.
