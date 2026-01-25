# OpsMaster

**OpsMaster** is a lightweight, idempotent Infrastructure-as-Code (IaC) engine built entirely in PowerShell.

It reads a declarative JSON blueprint (`blueprint.json`) and enforces the desired state on a local Windows machine. It functions similarly to tools like **Ansible** or **Puppet**, featuring "ChatOps" integration to alert Discord when drift is detected and fixed.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

* **Declarative Configuration:** Define your server's state in a simple `JSON` file.
* **Idempotency:** The script checks current state before making changes. If the system is already compliant, it does nothing.
* **Self-Healing:** Automatically restarts services, corrects files, and enforces Registry keys.
* **ChatOps Integration:** Sends real-time alerts to a Discord Webhook when remediation occurs.
* **Secure Design:** API keys and Webhooks are externalized to prevent credential leakage.

---

## Installation

1.  **Clone the Repository:**
    ```powershell
    git clone [https://github.com/YOUR_USERNAME/OpsMaster.git](https://github.com/YOUR_USERNAME/OpsMaster.git)
    cd OpsMaster
    ```

2.  **Verify Permissions:**
    Run as **Administrator** to manage Services and Registry keys.
    Ensure script execution is allowed:
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

3.  **Setup Secrets:**
    Create a file named `secrets.json` in the root folder.
    Paste your Discord Webhook URL inside:
    ```json
    {
        "DiscordWebhook": "[https://discord.com/api/webhooks/YOUR_KEY_HERE](https://discord.com/api/webhooks/YOUR_KEY_HERE)"
    }
    ```
    *Note: This file is git ignored to protect credentials.*

---

## Blueprint Configuration

Here we tell OpsMaster what it needs to check in thr `blueprint.json` file. 

### Example Blueprint
```json
{
    "ServerName": "Production-Web-01",
    "Config": {
        "Services": [
            { "Name": "Spooler", "State": "Stopped" }
        ],
        "Files": [
            { 
                "Path": "C:\\OpsMaster\\compliance.txt", 
                "Content": "Managed by OpsMaster." 
            }
        ],
        "Registry": [
            {
                "Path": "HKCU:\\Software\\OpsMaster",
                "Name": "LastScan",
                "Value": "1"
            }
        ]
    }
}

```

---

## Usage

Run the engine from a PowerShell terminal:

```powershell
.\OpsMaster.ps1
