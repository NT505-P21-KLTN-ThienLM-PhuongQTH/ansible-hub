vault policy write thesis-readonly - <<EOF
path "thesis/*" {
  capabilities = ["list", "read"]
}
EOF

vault auth enable -path=thesis-k8s kubernetes

vault write auth/thesis-k8s/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$SA_CA_CRT"

vault write auth/thesis-k8s/role/readonly \
  bound_service_account_names=vault-auth,vault-sa \
  bound_service_account_namespaces=vault,production \
  token_policies=thesis-readonly \
  ttl=24h

vault secrets enable -path=thesis -version=2 kv
