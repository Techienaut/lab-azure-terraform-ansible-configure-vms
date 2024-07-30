# lab-azure-terraform-ansible-configure-vms

VMs In Azure using Terraform, Ansible,Hashicorp Vault, and likely more.

# First Commit. A Working prototype of a lab that creates Windows 11 VMs in Azure

Does the following:

- ./start.sh script as an entry point
- Uses secrets.env to populate azure secrets and vm admin credentials into Hashicorp Vault
- Runs terraform apply (forced) and creates resources for vms that can be remotely access via WINRM HTTPS
- Runs an Ansible playbook and winrm pings the workstation vms.
