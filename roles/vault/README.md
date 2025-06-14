## Install & Configure Vault

### Phase 1 

1. Run the Install script: `install.sh`

2. Run the script below to init Vault server:

```
vault operator init
```

- The output should be:

```
Unseal Key 1: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Unseal Key 2: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Unseal Key 3: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Unseal Key 4: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Unseal Key 5: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Initial Root Token: xxxxxxxxxxxxxxxxxxxxx

Vault initialized with 5 key shares and a key threshold of 3. Please securely
distribute the key shares printed above. When the Vault is re-sealed,
restarted, or stopped, you must supply at least 3 of these keys to unseal it
before it can start servicing requests.

Vault does not store the generated root key. Without at least 3 keys to
reconstruct the root key, Vault will remain permanently sealed!

It is possible to generate new unseal keys, provided you have a quorum of
existing unseal keys shares. See "vault operator rekey" for more information.
```

3. Store the **Unseal Keys** and **Root Token** in the private place

4. Use 3 **Unseal Keys** to login to the Vault server by the command (Enter the command 3 times):

```
vault operator unseal
```

5. Enter the login command to login to Vault server, provides Root Token:

```
vault login
```

6. Access to Vault UI by URL to ensure Vault is unsealed and allow to access: https://vault.th1enlm02.live

7. Access to K8s cluster and create a Service Account for Vault server which using for authenticating to the K8s cluster, apply the file content below:

```
# https://developer.hashicorp.com/vault/tutorials/kubernetes/agent-kubernetes#agent-kubernetes
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: vault
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-secret
  namespace: vault
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
```

- Ensure the namespace **vault** was created:

```
apiVersion: v1
kind: Namespace
metadata:
  name: vault
```

8. Run the following command to create the **thesis-readonly** policy:

```
vault policy write thesis-readonly - <<EOF
path "thesis/*" {
  capabilities = ["list", "read"]
}
EOF
```

9. Run the command to enable Kubernetes authentication:

```
vault auth enable -path=thesis-k8s kubernetes
```

10. Provides the required variables below:

- SA_JWT_TOKEN: Server Account's JWT that created before: **vault-auth**
- K8S_HOST: Kubernetes API server endpoint.
- SA_CA_CRT: Kubernetes cluster's CA certificate

Create .env file and puts the variables in:
```
nano .env
SA_JWT_TOKEN=xxxxxxxxxxxxxxxxxxxxx
K8S_HOST=xxxxxxxxxxxxxxxxxxxxx
SA_CA_CRT=xxxxxxxxxxxxxxxxxxxxx
source .env
```

Run the configuration command:
```
vault write auth/thesis-k8s/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$SA_CA_CRT"
```

11. Run the command to create the readonly role:

```
vault write auth/thesis-k8s/role/readonly \
  bound_service_account_names=vault-auth,vault-sa \
  bound_service_account_namespaces=vault,production \
  token_policies=thesis-readonly \
  ttl=24h
```

- **Note**: There is 2 variables that need to take a look are **vault-sa** and **production**.
    - vault-sa: A Service Account needs to create for K8s pods use to authenticate to the Vault server.
    - production: Namespace that is using for deploying application pods.

12. Run the command to enable the KV secrets engine:

```
vault secrets enable -path=thesis -version=2 kv
```

13. Create the secrets for the applications:

Use this command to create secrets for each application:
```
vault kv put thesis/production/<application_name> @data.json
```
**Note**: Replace the application name and the related data (**data.json** content) for each application, using the name below:

- app-api:

```
cd /home/ubuntu/app-api
sudo nano data.json
vault kv put thesis/production/app-api @data.json
```
- ghtorrent-api:
```
cd /home/ubuntu/ghtorrent-api
sudo nano data.json
vault kv put thesis/production/ghtorrent-api @data.json
```
- model-api:
```
cd /home/ubuntu/model-api
sudo nano data.json
vault kv put thesis/production/model-api @data.json
```
- model-training:
```
cd /home/ubuntu/model-training
sudo nano data.json
vault kv put thesis/production/model-training @data.json
```

### Phase 2: K8s cluster setup

1. Install Vault Agent to K8s

```
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -f .\vault\values.yml
```

**Note**: Replace the values.yml path for real context. The values.yml content should be:

```
global:
  enabled: false
  namespace: vault
  externalVaultAddr: http://10.0.2.10:8200

injector:
  enabled: true
  logLevel: "debug"
  agentDefaults:
    cpuLimit: "200m"
    cpuRequest: "100m"
    memLimit: "128Mi"
    memRequest: "64Mi"
  authPath: "auth/thesis-k8s"
  logLevel: "debug"
```

2. Create the Service Account for pods:

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-sa
  namespace: production
```

3. Yeah, the last step is replace the patch files for Vault Agent inject secrets to application, the example content below:

```
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: production
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "readonly"
    vault.hashicorp.com/template-static-secret-render-interval: "10s"
    vault.hashicorp.com/agent-inject-secret-ghtorrent-api: "thesis/data/production/ghtorrent-api"
    vault.hashicorp.com/agent-inject-template-ghtorrent-api: |
      {{- with secret "thesis/data/production/ghtorrent-api" -}}
        {{- range $key, $value := .Data.data -}}
          export {{ $key }}="{{ $value }}" \n
        {{- end }}
      {{- end }}

spec:
  serviceAccountName: vault-sa
  containers:
    - name: app
      image: busybox
      command: [ "sh", "-c", "sleep 3600" ]
```
