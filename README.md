
# OpsMaster

**OpsMaster** is a lightweight, idempotent Infrastructure-as-Code (IaC) engine built entirely in PowerShell.

It reads a declarative JSON blueprint (`blueprint.json`) and enforces the desired state on a local Windows machine. It functions similarly to tools like **Ansible** or **Puppet**, but without the need for agents or complex master servers.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

* **Declarative Configuration:** Define your server's state in a simple `JSON` file.
* **Idempotency:** The script checks current state before making changes. If the system is already compliant, it does nothing.
* **Service Management:** Ensure critical services are Running or Stopped.
* **File Integrity:** Enforce the existence and content of specific files.
* **Registry Enforcement:** Manage Registry keys and values to harden system settings.
* **Detailed Logging:** Clear console output distinguishing between `[OK]` checks and `[FIXED]` actions.

---

## Installation

1.  **Clone the Repository:**
    ```powershell
    git clone [https://github.com/YOUR_USERNAME/OpsMaster.git](https://github.com/YOUR_USERNAME/OpsMaster.git)
    cd OpsMaster
    ```

2.  **Verify Permissions:**
    You must run this tool as **Administrator** to manage Services and Registry keys.
    
    Ensure script execution is allowed:
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

---

## Configuration

The brain of OpsMaster is the `blueprint.json` file. 

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

Run the engine from a PowerShell terminal with Administrator privileges:

```powershell
.\OpsMaster.ps1

```

### What happens next?

1. **Read:** The engine parses `blueprint.json`.
2. **Assess:** It checks the current status of every defined resource.
3. **Remediate:** * If a resource matches the blueprint, it logs `[OK]`.
* If a resource is different (Drift), it automatically corrects it and logs `[FIXED]`.



---

## Testing the "Self-Healing"

To see the engine in action:

1. **Break the state:** Manually start the `Print Spooler` service or delete the `compliance.txt` file.
2. **Run OpsMaster:** Execute `.\OpsMaster.ps1`.
3. **Verify:** Watch the console as OpsMaster detects the "Drift" and reverts your changes automatically.

---

## Roadmap

* Discord/Slack Webhook Integration (Notifications)
* Software Installation (Chocolately/Winget support)
* User & Group Management