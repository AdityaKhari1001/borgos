# Borgos — AI-First Multi-Agent OS with Zenith Coder & MCP

[![Releases](https://img.shields.io/badge/Releases-Download-blue?logo=github)](https://github.com/AdityaKhari1001/borgos/releases)

![Borgos network](https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1500&q=80)

A deployable, developer-focused operating layer for coordinating AI agents. Borgos brings Zenith Coder, Agent Zero, and MCP into one runtime. Use it to run coordinated workflows, integrate tooling, and build complex agent networks with clear APIs.

Badges
- [![agent-zero](https://img.shields.io/badge/agent--zero-enabled-green)](https://github.com/AdityaKhari1001/borgos)
- [![ai](https://img.shields.io/badge/ai-core-orange)](https://github.com/AdityaKhari1001/borgos)
- [![python](https://img.shields.io/badge/python-3.10%2B-blue)](https://github.com/AdityaKhari1001/borgos)
- [![docker](https://img.shields.io/badge/docker-ready-blue)](https://github.com/AdityaKhari1001/borgos)
- Topics: agent-zero • ai • automation • docker • fastapi • mcp • multi-agent • operating-system • python • zenith-coder

Key Release
- Download and run the latest release artifact from: https://github.com/AdityaKhari1001/borgos/releases
  - The release file contains the runnable artifact and setup steps. Download the appropriate file for your platform and execute it.

Table of contents
- What Borgos is
- Core components
- Architecture diagram
- Quick install (local, Docker)
- Minimal quickstart
- FastAPI integration
- MCP (Message Control Plane) guide
- Agent reference: Zenith Coder, Agent Zero
- Configuration
- Development & testing
- Contributing
- License & links

What Borgos is
Borgos is an OS-like runtime for multi-agent systems. It gives you:
- A process manager for agents.
- A message bus (MCP) for agent-to-agent coordination.
- Built-in agents: Zenith Coder (code generation and patching), Agent Zero (autonomy driver).
- REST API via FastAPI for control and metrics.
- Docker images for containerized deployments.

Core components
- Agent Manager: start, stop, monitor agents. Use it like a process manager for AI workers.
- MCP (Message Control Plane): brokerless pub/sub and RPC primitives built for agent state and task flow.
- Zenith Coder: a code-first agent that composes patches, tests, and releases changes.
- Agent Zero: a policy-driven agent for orchestration and autonomy tasks.
- API Gateway: FastAPI endpoints for interacting with agents and runtime.

Architecture diagram
![Architecture](https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1400&q=80)

- Agents run inside containers or local processes.
- MCP provides topics and channels.
- The control plane exposes REST and WebSocket endpoints.
- Storage supports logs, artifacts, and agent checkpoints.

Quick install (local)
1. Visit the releases page and get the release file:
   - Download the release artifact from https://github.com/AdityaKhari1001/borgos/releases
   - The archive contains a runnable binary or installer for your OS.

2. Example install steps (Linux example; adapt for Mac/Windows):
```bash
# download example artifact name; replace with actual file from Releases page
curl -L -o borgos-latest.tar.gz "https://github.com/AdityaKhari1001/borgos/releases/download/v1.0/borgos-linux-amd64.tar.gz"
tar -xzf borgos-latest.tar.gz
chmod +x borgos
./borgos server
```

3. Open the dashboard or API:
- Default HTTP: http://localhost:8080/api
- Web UI: http://localhost:8080/ui

Quick install (Docker)
- Borgos runs in Docker for production and CI.
```bash
# pull a published image (example tag)
docker pull adityakhari1001/borgos:latest

# run with local ports and a mounted config
docker run -d --name borgos \
  -p 8080:8080 \
  -v $(pwd)/borgos-config.yml:/etc/borgos/config.yml \
  adityakhari1001/borgos:latest
```

Minimal quickstart (run a sample agent)
1. Start Borgos server:
```bash
./borgos server
```
2. Register a sample agent using the API:
```bash
curl -X POST http://localhost:8080/api/agents \
  -H "Content-Type: application/json" \
  -d '{"name":"hello-agent","image":"ghcr.io/example/hello-agent:latest","command":["/start"]}'
```
3. Send a task to the agent:
```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"agent":"hello-agent","payload":{"type":"run","data":"print(\"hi\")"}}'
```
4. Watch logs:
```bash
curl http://localhost:8080/api/agents/hello-agent/logs
```

FastAPI integration
Borgos exposes a clean HTTP API built with FastAPI. Use the API to:
- Start and scale agents.
- Query MCP topics.
- Push code bundles to Zenith Coder.
- Retrieve execution traces and metrics.

Example Python client (requests):
```python
import requests

BASE = "http://localhost:8080/api"
r = requests.post(f"{BASE}/agents", json={
    "name": "builder",
    "image": "ghcr.io/example/builder:latest"
})
print(r.json())
```

MCP (Message Control Plane)
MCP provides topic-based messaging with guaranteed delivery options:
- Topics: ephemeral or persistent.
- Subscriptions: pull or push.
- RPC: request/response with timeouts and retries.

API examples:
- Publish:
```bash
curl -X POST http://localhost:8080/api/mcp/publish \
  -H "Content-Type: application/json" \
  -d '{"topic":"task.queue","message":{"task":"build","id":"abc123"}}'
```
- Subscribe (websocket or HTTP long-poll):
```bash
# WebSocket example URL
ws://localhost:8080/api/mcp/subscribe/task.queue
```

Agent reference

Zenith Coder
- Purpose: code synthesis, patch generation, test-run orchestration.
- Capabilities:
  - Generate code diffs from prompts.
  - Run unit tests in sandbox.
  - Produce release artifacts and patch notes.
- Integration:
  - Feed prompts via the API or MCP topic "zenith.requests".
  - Receive results on "zenith.results".
- Example workflow:
  - Send a feature prompt to Zenith.
  - Zenith returns a patch bundle and test report.
  - Use Agent Manager to apply patch to a build agent.

Agent Zero
- Purpose: autonomy driver and high-level planner.
- Capabilities:
  - Maintain internal goals and subgoals.
  - Call other agents through MCP.
  - Make decisions based on policy modules.
- Integration:
  - Use Agent Zero for orchestration tasks and fallback handling.
  - Monitor Agent Zero via the control API.

Configuration
- Config file: borgos-config.yml
- Key sections:
  - server: host, port, TLS
  - storage: type (local, s3), path, retention
  - agents: default images, resource limits
  - mcp: persistence, retention, partitions

Example config:
```yaml
server:
  host: 0.0.0.0
  port: 8080

storage:
  type: local
  path: /var/lib/borgos

agents:
  default_memory: 512m
  default_cpu: "0.5"

mcp:
  persistence: true
  retention_days: 7
```

Security
- Use TLS for public endpoints.
- Use API keys or OAuth for control plane access.
- Run agents in restricted containers with resource limits.

Observability
- Metrics endpoint: /metrics (Prometheus format)
- Traces: distributed tracing via OpenTelemetry
- Logs: per-agent log streams and retention policies

Development & testing
- Repo layout:
  - /agents — sample agent implementations
  - /pkg — core runtime libraries
  - /api — FastAPI endpoints
  - /scripts — helper scripts and CI hooks
- Run unit tests:
```bash
# run Python tests
pytest -q
# run integration scenario locally
./scripts/run-integration.sh
```
- Docker builds:
```bash
docker build -t borgos:dev .
```

Contributing
- Create issues for bugs and feature requests.
- Fork and open PRs for changes.
- Follow the code style guide (PEP8 for Python).
- Add tests for new features and agents.

Release and artifacts
- Check the releases page for binaries and images: https://github.com/AdityaKhari1001/borgos/releases
- Download the artifact that matches your OS and CPU.
- Follow the included run instructions inside the release archive.
- Example run (after download):
```bash
tar -xzf borgos-<platform>-v1.0.tar.gz
cd borgos
chmod +x borgos
./borgos server
```

Examples and recipes
- CI pipeline: run a ZenCoder patch step in CI, apply changes, run tests, deploy.
- Autoscale: use a horizontal scaler to spin up agents when MCP queue length grows.
- Local dev: use Docker Compose to run Borgos, a sample agent, and a mock MCP client.

Ecosystem and extensions
- Third-party agents: build and publish agents to a registry.
- Plugins: auth backends, storage adapters, custom MLP models.
- SDKs: small clients for Python, Go, and JS (examples in /sdk).

Links
- Releases: https://github.com/AdityaKhari1001/borgos/releases
- Topics: agent-zero • ai • automation • docker • fastapi • mcp • multi-agent • operating-system • python • zenith-coder

License
- MIT (see LICENSE file)

Contact
- Open an issue on the repo for bugs and feature requests.
- Use PRs for code changes and documentation updates.

Screenshots
![Agents dashboard](https://images.unsplash.com/photo-1526378720088-9a0b94e3f7c5?auto=format&fit=crop&w=1400&q=80)
- Dashboard shows agent status, MCP topic metrics, and logs.

Changelog
- Check the Releases page for a full changelog and release artifacts:
  - https://github.com/AdityaKhari1001/borgos/releases

Developer notes
- Borgos favors small, focused agents.
- Keep the MCP messages typed and versioned.
- Keep agent images minimal to speed scale operations.