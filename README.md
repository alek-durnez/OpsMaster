# WinStateEnforcer

**WinStateEnforcer** is a local Infrastructure-as-Code (IaC) engine for Windows.

It parses a declarative JSON blueprint (`blueprint.json`) to validate and enforce the state of Services, Files, Registry Keys, and Software packages. When configuration drift is detected, it attempts to self-heal the system and logs the remediation events to a local file or Discord webhook.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

---

## Capabilities

* **Service Enforcement:** Ensure critical services are running (or stopped).
* **Software Provisioning:** * **Chocolatey Wrapper:** Bootstraps Chocolatey to install/update repository packages.
    * **Direct Install:** Downloads and executes standalone `.exe` installers silently.
* **File Integrity:** Ensures specific configuration files exist with exact content.
* **Registry Management:** Enforces specific keys and values for system tuning.
* **Drift Alerting:** Sends JSON-formatted alerts to a Webhook (Discord) upon remediation.

---

## Installation

1.  **Clone the Repository:**
    ```powershell
    git clone [https://github.com/alek-durnez/WinStateEnforcer.git](https://github.com/alek-durnez/WinStateEnforcer.git)
    cd WinStateEnforcer
    ```

2.  **Prerequisites:**
    * Windows 10/11 or Server 2016+
    * PowerShell 5.1 or newer
    * Administrator Privileges (Required for Service/Registry write access)

3.  **Secrets Configuration:**
    Create a `secrets.json` file in the root directory to store sensitive data.
    ```json
    {
        "DiscordWebhook": "[https://discord.com/api/webhooks/](https://discord.com/api/webhooks/)..."
    }
    ```
    *(Note: This file is excluded from git via .gitignore)*

---

## Configuration

The engine uses `settings.json` for runtime behavior and `blueprint.json` for the target state definition.

### 1. Runtime Settings (`settings.json`)
Controls logging paths and toggle switches for notifications.

```json
{
    "BlueprintPath": ".\\blueprint.json",
    "SecretsPath": ".\\secrets.json",
    "LogPath": "C:\\ProgramData\\WinStateEnforcer\\Logs\\Engine.log",
    "Notifications": {
        "Enabled": true,
        "Provider": "Discord"
    }
}

```

### 2. Desired State Blueprint (`blueprint.json`)

Defines the resources to be enforced.

```json
{
    "ServerName": "Prod-Web-Node-01",
    "Config": {
        "Services": [
            { "Name": "Spooler", "State": "Stopped" },
            { "Name": "wuauserv", "State": "Running" }
        ],
        "Software": [
            {
                "Name": "Firefox",
                "Provider": "Chocolatey",
                "PackageId": "firefox"
            },
            {
                "Name": "LegacyApp",
                "Provider": "Direct",
                "CheckPath": "C:\\Apps\\Legacy\\app.exe",
                "Url": "http://internal-repo/legacy-app.exe",
                "SilentArgs": "/quiet"
            }
        ],
        "Registry": [
            {
                "Path": "HKCU:\\Software\\WinStateEnforcer",
                "Name": "LastAudit",
                "Value": "1"
            }
        ]
    }
}

```

---

## Usage

**Interactive Execution:**
Open PowerShell as Administrator and run:

```powershell
.\WinStateEnforcer.ps1

```

**Scheduled Task (Unattended):**
To run as a background compliance agent:

```powershell
# Task Scheduler Arguments
-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Tools\WinStateEnforcer\WinStateEnforcer.ps1"

```

---

## License

MIT License. See [LICENSE](https://www.google.com/search?q=./LICENSE) for full text.