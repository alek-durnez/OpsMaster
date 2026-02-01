# OpsMaster

**OpsMaster** is a lightweight, idempotent Infrastructure-as-Code (IaC) engine built in PowerShell.

It reads a declarative JSON blueprint (`blueprint.json`) and enforces the desired state on a local Windows machine. It functions similarly to tools like **Ansible** or **Puppet**, featuring "ChatOps" integration to alert Discord when drift is detected and fixed.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

---

## Features

* **Declarative Configuration:** Define your server's state in a simple `JSON` file.
* **Idempotency:** Checks current state before acting. If the system is compliant, it does nothing.
* **Software Management:** Checks for installed software and silently installs missing packages (e.g., 7-Zip, Chrome).
* **Self-Healing:** Automatically restarts services, corrects files, and enforces Registry keys.
* **ChatOps Integration:** Sends real-time alerts to a Discord Webhook when remediation occurs.
* **Secure Design:** API keys and Webhooks are externalized to prevent credential leakage.

---

## Installation

1.  **Clone the Repository:**
    ```powershell
    git clone [https://github.com/alek-durnez/OpsMaster.git](https://github.com/alek-durnez/OpsMaster.git)
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
    *Note: This file is git-ignored to protect credentials.*

---

## Configuration

OpsMaster relies on three configuration files:

1.  **`blueprint.json`**: The desired state of the server (What to manage).
2.  **`settings.json`**: App configuration (Logging paths, feature toggles).
3.  **`secrets.json`**: Credentials (API Keys).

### Example Blueprint (`blueprint.json`)
```json
{
    "ServerName": "Production-Web-01",
    "Config": {
        "Services": [
            { "Name": "Spooler", "State": "Stopped" }
        ],
        "Software": [
            {
                "Name": "7-Zip",
                "CheckPath": "C:\\Program Files\\7-Zip\\7z.exe",
                "Url": "[https://www.7-zip.org/a/7z2409-x64.exe](https://www.7-zip.org/a/7z2409-x64.exe)",
                "SilentArgs": "/S"
            }
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

### Example Settings (`settings.json`)

```json
{
    "BlueprintPath": ".\\blueprint.json",
    "SecretsPath": ".\\secrets.json",
    "LogPath": "C:\\OpsMaster\\Logs\\OpsMaster.log",
    "Notifications": {
        "Enabled": true,
        "Provider": "Discord"
    }
}

```

---

## Usage

**Manual Run:**
Run the engine from a PowerShell terminal with Admin privileges:

```powershell
.\OpsMaster.ps1

```

**Automated (Self-Healing Mode):**
To ensure continuous compliance, schedule the script to run hourly via **Task Scheduler**:

1. Create a new Task running with **Highest Privileges**.
2. **Action:** `Start a program` -> `powershell.exe`
3. **Arguments:**
```text
-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\To\OpsMaster\OpsMaster.ps1"