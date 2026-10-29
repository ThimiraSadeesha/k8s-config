#!/usr/bin/env bash
# Run on the VPS after applying cluster/ci-rbac.yaml.
# Usage: ./make-ci-kubeconfig.sh dev|prod [api-server-url]
#
# Writes a kubeconfig for the namespace-limited ci-deployer account, base64-encoded for use as the
# GitHub secret KUBE_CONFIG_DEV / KUBE_CONFIG_PROD. The file holds a credential: copy it, then delete it.
set -euo pipefail
NS="${1:?usage: $0 dev|prod [api-server-url]}"
SERVER="${2:-https://51.79.158.90:6443}"
OUT="$HOME/ci-kubeconfig-$NS.b64"

TOKEN=$(kubectl -n "$NS" get secret ci-deployer-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n "$NS" get secret ci-deployer-token -o jsonpath='{.data.ca\.crt}')   # already base64
[ -n "$TOKEN" ] && [ -n "$CA" ] || { echo "token not ready yet; wait a few seconds and retry" >&2; exit 1; }

KCFG=$(mktemp)
trap 'rm -f "$KCFG"' EXIT
cat > "$KCFG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: k3s
  cluster:
    server: $SERVER
    certificate-authority-data: $CA
users:
- name: ci-deployer-$NS
  user:
    token: $TOKEN
contexts:
- name: ci-$NS
  context: { cluster: k3s, user: ci-deployer-$NS, namespace: $NS }
current-context: ci-$NS
EOF

umask 077
base64 < "$KCFG" | tr -d '\n' > "$OUT"

echo "== checking what the account can and cannot do in '$NS'"
check() { # description, expected, kubectl auth can-i args...
  local desc="$1" want="$2"; shift 2
  local got; got=$(kubectl --kubeconfig="$KCFG" auth can-i "$@" 2>/dev/null || true)
  [ "$got" = "$want" ] && echo "  ok   $desc ($got)" || echo "  FAIL $desc (wanted $want, got '${got:-unreachable}')"
}
check "patch deployments"        yes patch deployments.apps
check "read secrets"             no  get secrets
check "delete deployments"       no  delete deployments.apps
check "see other namespaces"     no  get pods -n kube-system
echo
echo "kubeconfig (base64) written to: $OUT"
echo "Copy it into the GitHub secret, then:  rm $OUT"
