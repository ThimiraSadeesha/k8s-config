#!/usr/bin/env bash
# Usage: ./create-secrets.example.sh dev|prod
# Creates DB and app secrets directly in the cluster. Never commit real values.
set -euo pipefail
NS="${1:?usage: $0 dev|prod}"

PG_ROOT=$(openssl rand -hex 16)
MARIA_ROOT=$(openssl rand -hex 16)
NEST_DB_PASS=$(openssl rand -hex 16)
GO_DB_PASS=$(openssl rand -hex 16)

kubectl -n "$NS" create secret generic postgres-secret --from-literal=POSTGRES_PASSWORD="$PG_ROOT"
kubectl -n "$NS" create secret generic mariadb-secret  --from-literal=MARIADB_ROOT_PASSWORD="$MARIA_ROOT"

# Nest -> Postgres, Go -> MariaDB (swap to match your real mapping)
kubectl -n "$NS" create secret generic k8s-app-api-secrets \
  --from-literal=DATABASE_URL="postgres://nest_app:${NEST_DB_PASS}@postgres:5432/nest_app"
kubectl -n "$NS" create secret generic k8s-app-backend-secrets \
  --from-literal=DATABASE_URL="go_app:${GO_DB_PASS}@tcp(mariadb:3306)/go_app"

echo "Now create the per-app databases/users once the DB pods are Ready:"
echo "  kubectl -n $NS exec -it postgres-0 -- psql -U postgres -c \"CREATE USER nest_app PASSWORD '$NEST_DB_PASS'; CREATE DATABASE nest_app OWNER nest_app;\""
echo "  kubectl -n $NS exec -it mariadb-0 -- mariadb -uroot -p\"$MARIA_ROOT\" -e \"CREATE DATABASE go_app; CREATE USER 'go_app'@'%' IDENTIFIED BY '$GO_DB_PASS'; GRANT ALL ON go_app.* TO 'go_app'@'%';\""
