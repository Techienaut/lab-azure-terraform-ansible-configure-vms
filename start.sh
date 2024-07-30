#!/bin/bash

# ==FUNCTIONS==
# Function to check if Vault is installed
check_vault_installed() {
    if ! command -v vault &> /dev/null; then
        echo "Vault is not installed. Installing Vault..."
        install_vault
    else
        echo "Vault is already installed."
    fi
}

# Function to install Vault
install_vault() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew tap hashicorp/tap
        brew install hashicorp/tap/vault
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
        sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
        sudo apt-get update && sudo apt-get install vault
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi
}

# ==MAIN EXECUTION==
# Check if Vault is installed
check_vault_installed

# Export Vault address
export VAULT_ADDR='http://127.0.0.1:8200'
vault server -config config_vault.hcl &

# Wait for Vault server to start
sleep 5

# Initialize Vault server if not already initialized
if [ ! -f ~/.vault-token ]; then
    vault operator init -key-shares=1 -key-threshold=1 > ~/.vault-init
    VAULT_TOKEN=$(cat ~/.vault-init | grep "Initial Root Token" | awk '{print $4}')
    echo $VAULT_TOKEN > ~/.vault-token
fi

# Save the Vault root token
VAULT_TOKEN=$(cat ~/.vault-token)
echo $VAULT_TOKEN

# Unseal Vault
vault operator unseal $(cat ~/.vault-init | grep "Unseal Key" | awk '{print $4}')

# If secrets engine is not enabled, enable it
if ! vault secrets list | grep -q "secret/"; then
    vault secrets enable -path=secret kv
fi
# vault secrets disable secret # To disable the secrets engine

# Login to Vault
vault login $VAULT_TOKEN

# If secrets.env file exists, source it, set to environment variables, and add to Vault
if [ -f secrets.env ]; then
    # Import secrets.env as environment variables
    export $(cat secrets.env | xargs)
    vault kv put secret/azure client_id=$CLIENT_ID client_secret=$CLIENT_SECRET subscription_id=$SUBSCRIPTION_ID tenant_id=$TENANT_ID
    vault kv put secret/ad ad_admin_username=$AD_ADMIN_USERNAME ad_admin_password=$AD_ADMIN_PASSWORD
fi

# Initialize and apply Terraform configuration
terraform init
terraform apply -auto-approve


# Fetch secrets for Ansible playbook
ADMIN_USERNAME=$(vault kv get -field=ad_admin_username secret/ad)
ADMIN_PASSWORD=$(vault kv get -field=ad_admin_password secret/ad)
echo "Admin username: $ADMIN_USERNAME"
echo "Admin password: $ADMIN_PASSWORD"

export admin_username=$ADMIN_USERNAME
export admin_password=$ADMIN_PASSWORD
export workstations_ips=$(terraform output -json workstations_ips | jq -r '.[]')

# Get workstation IPs from Terraform output
WORKSTATIONS_IPS=$(terraform output -json workstations_ips | jq -r '.[]')
echo "Workstation IPs: $WORKSTATIONS_IPS"

# Set environment variable to avoid macOS fork() issue
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# Run Ansible playbook with necessary variables
pipenv run ansible-playbook playbook_workstations.yml -vvv \
    -e "admin_username=$ADMIN_USERNAMEe" \
    -e "admin_password=$ADMIN_PASSWORD" \
    -e "workstations_ips=$WORKSTATIONS_IPS"

# Stop Vault server dev and cleanup
kill $(ps aux | grep '[v]ault server' | awk '{print $2}')
