#!/usr/bin/env python3

import json
import os

def main():
    # Get environment variables passed from the script
    admin_username = os.getenv('admin_username')
    admin_password = os.getenv('admin_password')
    workstations_ips = os.getenv('workstations_ips').split()

    # Create dynamic inventory
    inventory = {
        "workstations": {
            "hosts": workstations_ips,
            "vars": {
                "ansible_user": admin_username,
                "ansible_password": admin_password,
                "ansible_port": 5986,
                "ansible_connection": "winrm",
                "ansible_winrm_transport": "ntlm",
                "ansible_winrm_server_cert_validation": "ignore"
            }
        }
    }

    print(json.dumps(inventory))

if __name__ == "__main__":
    main()