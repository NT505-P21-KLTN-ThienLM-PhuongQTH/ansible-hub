#!/bin/bash

sudo apt update && sudo apt install gpg wget
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault

sudo mkdir -p /mnt/vault/data
sudo chown -R vault:vault /mnt/vault
sudo chmod -R 750 /mnt/vault

sudo tee /etc/vault.d/vault.hcl <<EOF > /dev/null
ui = true
cluster_addr  = "http://127.0.0.1:8201"
api_addr      = "http://127.0.0.1:8200"

storage "raft" {
  path = "/mnt/vault/data"
  node_id = "1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable = 1
}
EOF

sudo tee /lib/systemd/system/vault.service <<EOF > /dev/null
[Unit]
Description="HashiCorp Vault"
Documentation="https://developer.hashicorp.com/vault/docs"
ConditionFileNotEmpty="/etc/vault.d/vault.hcl"

[Service]
User=vault
Group=vault
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP
KillMode=process
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /lib/systemd/system/vault.service

sudo systemctl daemon-reload
sudo systemctl enable vault.service
sudo systemctl start vault.service

# export VAULT_ADDR=http://localhost:8200
# vault operator init
