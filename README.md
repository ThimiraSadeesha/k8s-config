# k8s-config

Kubernetes manifests for the k3s VPS. This repo is the source of truth for what runs in the
`dev` and `prod` namespaces; the app repos build images and CI records the new tag here.

```
cluster/   one-time cluster objects: namespaces + quotas, TLS issuer, network policies, CI RBAC
config/    Kustomize base + overlays/dev + overlays/prod
scripts/   create-secrets.example.sh (DB + app secrets), make-ci-kubeconfig.sh
monitoring/ Grafana + VictoriaMetrics (metrics, 7 days), applied by hand: kubectl apply -k monitoring
```

| App repo | Image |
|---|---|
| `k8s-app-api` | `ghcr.io/thimirasadeesha/k8s-app-api` |
| `k8s-app-ui` | `ghcr.io/thimirasadeesha/k8s-app-ui` |
| `k8s-app` (ZENT: Next.js UI + FastAPI API) | `k8s-app-frontend` and `k8s-app-backend` |

Hosts: `dev-k8s.auren.rest` / `api.dev-k8s.auren.rest` / `dev.zent.auren.rest` (dev), `k8s.auren.rest` / `api.k8s.auren.rest` / `zent.auren.com` (prod).

## Apply by hand (on the VPS)

```bash
git pull
kubectl apply -k config/overlays/dev
```

## CI deploy: one-time setup

A push to `dev` builds the image, writes its tag into `config/overlays/dev/kustomization.yaml`
here, then applies the overlay. A push to `main` does the same for prod, after approval.

**1. On the VPS: create the CI accounts and a kubeconfig**

```bash
kubectl apply -f cluster/ci-rbac.yaml
./scripts/make-ci-kubeconfig.sh dev
```

The script prints a permission check (it can patch deployments in `dev`, and cannot read secrets,
delete, or touch other namespaces) and writes `~/ci-kubeconfig-dev.b64`. Copy its contents into the
GitHub secret below, then `rm` the file. Do `prod` later, when prod is ready.

The kubeconfig points at `https://51.79.158.90:6443`, so that port must be reachable from GitHub's
runners. The account is limited to one namespace, but the API port is public; keep it that way
only while CI needs it.

**2. On GitHub: a token for this repo**

Settings > Developer settings > Fine-grained tokens: repository access `k8s-config` only,
permission Contents = read and write. This is `CONFIG_REPO_TOKEN`.

**3. On GitHub: secrets in each app repo** (`k8s-app-api`, `k8s-app-ui`, later `k8s-app`)

Settings > Secrets and variables > Actions > New repository secret:

| Secret | Value |
|---|---|
| `KUBE_CONFIG_DEV` | contents of `~/ci-kubeconfig-dev.b64` |
| `CONFIG_REPO_TOKEN` | the token from step 2 |
| `KUBE_CONFIG_PROD` | only once prod exists |

**4. On GitHub: environments** in each app repo (Settings > Environments)

- `dev`: no rules.
- `prod`: add Required reviewers (yourself). Without this, a push to `main` deploys to prod
  immediately.

**5. Make the image packages public** (one time, after each image's first push)

GitHub profile > Packages > the package > Package settings > Change visibility. The cluster pulls
anonymously, so there is no pull secret.

## Notes

- Tags are the 8-character commit SHA; never `latest`.
- Rotating the CI credential: delete the `ci-deployer-token` secret in the namespace, re-apply
  `cluster/ci-rbac.yaml`, and run `make-ci-kubeconfig.sh` again.

## Monitoring (Grafana, free self-hosted)

Runs in the `monitoring` namespace (~340Mi RAM) at `https://grafana.auren.rest`. Not deployed by CI:
the CI account only has access to dev and prod.

```bash
# DNS first: grafana.auren.rest -> 51.79.158.90
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl apply -k monitoring
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Log in as `admin`, then Dashboards > New > Import and enter an ID: `1860` (node), `15757` (cluster),
`15760` (pods). Pick the `VictoriaMetrics` data source.
