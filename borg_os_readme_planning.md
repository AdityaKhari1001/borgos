# BorgOS – Technical Specification for Autonomous Builders

*Version: 2025‑08‑08 • Status: α‑0.3*

---

## 0️⃣  Purpose of This Document

This spec is **machine‑readable** and **agent‑friendly**.  Every section is written so that an LLM‑powered build‑agent can:

1. **Clone** → 2. **Assemble** → 3. **Test** → 4. **Package ISO** → 5. **Publish artifacts** without human intervention.

Agents should follow the order of sections; each subsection contains:

- **Goals**  (what must exist when section succeeds)
- **Inputs** (files / repos / env vars)
- **Outputs** (files / services / commits)
- **Steps** (idempotent commands)

Human engineers can skim narrative boxes (`💬`), agents may ignore them.

---

## 1️⃣  Global Parameters (env‑vars)

| Variable             | Example           | Description                                   |
| -------------------- | ----------------- | --------------------------------------------- |
| `BORG_BRANCH`        | `main`            | Git branch to build from                      |
| `ISO_TAG`            | `borgos-20250808` | Tag name for resulting ISO & container images |
| `OPENAI_API_KEY`     | `sk-…`            | Optional, enables online LLM fallback         |
| `BORG_OFFLINE_MODEL` | `phi3:instruct`   | Model pulled via **Ollama**                   |

Agents must **export** these before any build step.

---

## 2️⃣  Repository Layout (canonical)

```
root/
 ├─ iso-builder/         # live-build driver
 │   ├─ borgos_iso_builder.sh  # single entrypoint
 │   └─ config/ …
 ├─ installer/           # post‑install script (idempotent)
 │   └─ install_all.sh
 ├─ webui/               # Flask app
 │   ├─ app.py
 │   └─ requirements.txt
 ├─ mcp_servers/
 │   └─ fs_server.py
 ├─ docs/
 │   └─ (this file)
 └─ .ci/                 # GitHub Actions / Drone pipelines
```

Agents must **mirror** exactly this tree when generating tar/zip artefacts.

---

## 3️⃣  Build‑Stage Matrix

| Stage               | Container          | Script                              | Artifact                          |
| ------------------- | ------------------ | ----------------------------------- | --------------------------------- |
| **S0** – Lint       | `python:3.11-slim` | `.ci/lint.sh`                       | pass/fail status                  |
| **S1** – Unit‑tests | `python:3.11`      | `.ci/test.sh`                       | coverage report                   |
| **S2** – ISO build  | `debian:12`        | `iso-builder/borgos_iso_builder.sh` | `out/ISO/${ISO_TAG}.iso`          |
| **S3** – Docker     | `docker:24`        | `.ci/docker_build.sh`               | `ghcr.io/borgos/webui:${ISO_TAG}` |
| **S4** – Release    | `node:20-slim`     | `.ci/release.sh`                    | GitHub draft release              |

Agents execute matrix sequentially; fail‑fast if any stage non‑zero.

---

## 4️⃣  Detailed Assembly Steps

### 4.1  Lint & Security Scan

**Goals**: all bash / python files pass shellcheck + ruff + bandit. **Inputs**: entire repo **Outputs**: `artifacts/lint-report.html` **Steps**:

```bash
pip install ruff bandit
ruff .
bandit -r installer webui mcp_servers -o artifacts/lint-report.html -f html
shellcheck $(git ls-files '*.sh')
```

### 4.2  Unit Tests (Python)

**Goals**: ≥90 % coverage on webui + CLI wrapper. **Inputs**: `webui/app.py` `installer/install_all.sh`

```bash
pip install -r webui/requirements.txt pytest coverage
coverage run -m pytest tests/
coverage xml && coverage html
```

### 4.3  ISO Build

**Goals**: produce bootable hybrid ISO ≤ 2 GB. **Inputs**: `iso-builder/borgos_iso_builder.sh` **plus** env vars.

```bash
sudo bash iso-builder/borgos_iso_builder.sh
ls -lh borgos-*.iso > artifacts/iso_list.txt
```

### 4.4  Docker Image for WebUI

**Goals**: publish OCI image containing Flask dashboard. **Dockerfile** (implicit):

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY webui/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY webui/ .
EXPOSE 6969
CMD ["python","app.py"]
```

**Build**: `docker build -t ghcr.io/borgos/webui:${ISO_TAG} .` **Push**: `docker push ghcr.io/borgos/webui:${ISO_TAG}`

### 4.5  Release Draft

**Goals**: create GitHub release with checksums & changelog.

```bash
echo "## Checksums" > notes.md
sha256sum out/ISO/${ISO_TAG}.iso >> notes.md
gh release create ${ISO_TAG} out/ISO/${ISO_TAG}.iso -F notes.md --draft
gh release upload ${ISO_TAG} artifacts/lint-report.html
```

---

## 5️⃣  Runtime Architecture (on‑device)

```
          ┌─────────────┐
          │  User / CLI │
          └──────┬──────┘
                 │ natural language
           borg (wrapper)  ↔  Ollama daemon
                 │                │
         ┌───────┼────────────────┼───────┐
         │       │ online (HTTP) │       │
     ChromaDB  OpenRouter   WebUI Flask  MCP tools
         │           │             │        │
     vector mem   GPT‑4 family   Dashboard  Filesystem / COM
```

- All services are managed via **systemd** units created by `installer/install_all.sh`.
- Default ports: 22 SSH, 80/443 Nginx, 6969 WebUI, 5678 n8n, 7300 MCP‑fs.

---

## 6️⃣  Extensibility Contracts

### 6.1  Borg CLI Plugin (Python)

```python
# drop into /opt/borgos/plugins/hello.py
from borg.plugin import Tool
@Tool(name="hello", desc="Say hi")
async def hello(name: str="world"):
    return f"Hello {name}!"
```

Installer auto‑discovers `*.py` under plugins and registers via MCP.

### 6.2  Pre‑seed Profiles (YAML)

```yaml
profile: edge-iot
services:
  - nginx
  - mcp
  - com-monitor
offline_model: phi3:instruct
```

`installer.sh --profile edge-iot` reads YAML to enable/disable units.

---

## 7️⃣  FAQ for Build‑Agents

| Q                                  | A                                                                |
| ---------------------------------- | ---------------------------------------------------------------- |
| **What if live‑build mirror 404?** | Retry with `deb.debian.org` fallback list (script auto‑detects). |
| **Cannot reach OpenRouter**        | Agent sets `OFFLINE_ONLY=true` and continues; ISO still valid.   |
| **Disk full**                      | Clean `/var/cache/apt`, prune Docker, or split stages.           |

---

## 8️⃣  Future Work (Backlog)

- ArchISO flavour (task id `OS‑ALT‑ARCHISO`).
- OTA delta‑upgrade via `borg upgrade` (task id `CORE‑UPDATER`).
- Multi‑user permission model for `borg` command (task id `SEC‑ACL`).

---

**End of Spec** – agents may now execute Stage Matrix starting at S0.

