# MCP Client CLI Guide

This guide documents how to interact with MCP servers using both Ink-based CLI experience and the existing Python `mcp_client.py` command-line interface.

## Table of Contents
- [Overview](#overview)
- [Ink CLI (Interactive)](#ink-cli-interactive)
- [Authentication](#authentication)
- [Basic Commands](#basic-commands)
- [Server Management Commands](#server-management-commands)
- [Tool Discovery](#tool-discovery)
- [Direct Server Access](#direct-server-access)

## Overview

You now have two choices:
- `cli/src/index.tsx` — An interactive Ink CLI with rich terminal UI, quick command shortcuts, and JSON viewer support.
- `cli/mcp_client.py` — The original Python CLI that remains available for scripting, automation, or environments without Node.js.

Both clients share the same authentication rules and produce identical JSON payloads for `ping`, `list`, `call`, and `init`.

## Ink CLI (Interactive)

The Ink CLI now behaves like a chat-style operator powered by [Ink](https://github.com/vadimdemedes/ink) and `tsx`. It automatically discovers ingress tokens, supports Keycloak M2M flows, and lets you mix natural questions with explicit `/commands` to drive the registry tooling.

### Quick start
```bash
cd cli
npm install   # installs Ink, React, and TypeScript helpers
npm run start # launches the conversational CLI (use `npm run dev` for watch mode)
```

What to expect:
- The header reports which tokens were discovered and when they expire.
- Type messages freely; start a slash-command to run something immediately.
- `/help` prints the full catalogue; `/retry` re-runs authentication if needed.
- Set `ANTHROPIC_API_KEY` in your environment to let the assistant call Claude automatically; otherwise it stays in manual mode.

### Chat commands

Core MCP actions:
- `/ping`, `/list`, `/init`
- `/call tool=current_time_by_timezone args='{"tz_name":"America/New_York"}'`

Agent mode (when `ANTHROPIC_API_KEY` is set):
- Ask naturally (e.g. “monitor the services” or “register the currenttime config”) and Claude will decide which command to run.
- The assistant may output intermediate tool logs before summarising the result.
- Override the model with `ANTHROPIC_MODEL` (defaults to `claude-3-5-sonnet-latest`).

Service toolkit (`service_mgmt.sh` under the hood):
- `/service add configPath=cli/examples/server-config.json`
- `/service delete servicePath=/example-server serviceName=example-server`
- `/service monitor` (all services) or `/service monitor configPath=cli/examples/server-config.json`
- `/service add-groups serverName=example-server groups=mcp-servers-restricted/read`
- `/service create-group groupName=mcp-servers-team/read description="Team read access"`
- `/service list-groups`

Registry imports (`import_from_anthropic_registry.sh`):
- `/import dry`
- `/import apply importList=cli/import_server_list.txt`

User & M2M management (`user_mgmt.sh`):
- `/user create-m2m name=agent-finance groups=mcp-servers-finance/read`
- `/user create-human username=jdoe email=jdoe@example.com firstName=John lastName=Doe groups=mcp-servers-restricted/read`
- `/user delete username=agent-finance`
- `/user list`, `/user list-groups`

Diagnostics (`test_anthropic_api.py`):
- `/diagnostic run-suite tokenFile=.oauth-tokens/ingress.json baseUrl=http://localhost`
- `/diagnostic run-test tokenFile=.oauth-tokens/ingress.json testName=list-servers`

### Non-interactive usage
You can run the same entry-point in batch mode for pipelines or quick checks:
```bash
# Equivalent to `python3 cli/mcp_client.py ping`
npx tsx src/index.tsx -- --command ping --url http://localhost:7860/mcpgw/mcp

# Explicit token file with JSON output
npx tsx src/index.tsx -- --command list --token-file ~/.mcp/ingress_token --json

# Call a tool
npx tsx src/index.tsx -- \
	--command call \
	--tool current_time_by_timezone \
	--args '{"tz_name":"America/New_York"}'
```

> 💡 Append `--interactive` to force chat mode even when a command is provided, or `--no-interactive` to suppress any UI.

## Authentication

The client supports two authentication methods:

### 1. M2M (Machine-to-Machine) Authentication
Set environment variables for M2M authentication:
```bash
export CLIENT_ID=your_client_id
export CLIENT_SECRET=your_client_secret
export KEYCLOAK_URL=http://localhost:8080
export KEYCLOAK_REALM=mcp-gateway
```

Or source a credentials file:
```bash
source .oauth-tokens/agent-test-agent-m2m.env
```

### 2. Ingress Token Authentication
The client will automatically load ingress tokens from `.oauth-tokens/ingress.json` if M2M credentials are not available.

## Basic Commands

### Test Connectivity (Ping)
```bash
# Ping the default gateway
uv run cli/mcp_client.py ping

# Ping a specific endpoint
uv run cli/mcp_client.py --url http://localhost/currenttime/mcp ping
```

### List Available Tools
```bash
# List tools from the default gateway
uv run cli/mcp_client.py list

# List tools from a specific server
uv run cli/mcp_client.py --url http://localhost/currenttime/mcp list
```

## Server Management Commands

### List All Registered Services
```bash
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool list_services \
	--args '{}'
```

Returns a dictionary containing:
- `services`: List of service information with details like name, path, status
- `total_count`: Total number of registered services

### Register a New Service
```bash
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool register_service \
	--args '{
    "server_name": "Minimal Server",
    "path": "/minimal-server",
    "proxy_pass_url": "http://minimal-server:8000",
    "description": "A minimal MCP server example",
    "tags": ["example", "minimal"],
    "num_tools": 2,
    "num_stars": 0,
    "is_python": true,
    "license": "MIT"
  }'
```

**Register from a JSON file:**
```bash
# Register a service using configuration from a JSON file
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool register_service \
	--args "$(cat cli/examples/server-config.json)"
```

**Required parameters:**
- `server_name`: Display name for the server
- `path`: Unique URL path prefix (must start with '/')
- `proxy_pass_url`: Internal URL where the MCP server is running

**Optional parameters:**
- `description`: Description of the server (default: "")
- `tags`: List of tags for categorization (default: null)
- `num_tools`: Number of tools provided (default: 0)
- `num_stars`: Star rating for the server (default: 0)
- `is_python`: Whether implemented in Python (default: false)
- `license`: License information (default: "N/A")

### Remove a Service
```bash
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool remove_service \
	--args '{"service_path": "/my-service"}'
```

**Example:**
```bash
# Remove minimal-server
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool remove_service \
	--args '{"service_path": "/minimal-server"}'
```

### Toggle Service State (Enable/Disable)
```bash
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool toggle_service \
	--args '{"service_path": "/my-service"}'
```

### Health Check
Get health status for all registered servers:
```bash
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool healthcheck \
	--args '{}'
```

## Tool Discovery

### Find Tools Using Natural Language
Use the intelligent tool finder to discover tools based on natural language queries:

```bash
# Find tools for getting current time
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool intelligent_tool_finder \
	--args '{"natural_language_query": "get current time in New York", "top_n_tools": 3}'

# Find tools by tags only
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool intelligent_tool_finder \
	--args '{"tags": ["time", "timezone"], "top_n_tools": 5}'

# Combine natural language and tags
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool intelligent_tool_finder \
	--args '{
    "natural_language_query": "get current time",
    "tags": ["time"],
    "top_k_services": 3,
    "top_n_tools": 5
  }'
```

**Parameters:**
- `natural_language_query`: Natural language description (optional if tags provided)
- `tags`: List of tags to filter by (optional)
- `top_k_services`: Number of top services to consider (default: 3)
- `top_n_tools`: Number of best tools to return (default: 1)

## Direct Server Access

### Call Tools on Specific Servers

#### Current Time Service
```bash
# Get current time in a specific timezone
uv run cli/mcp_client.py --url http://localhost/currenttime/mcp call \
	--tool current_time_by_timezone \
	--args '{"tz_name": "America/New_York"}'

# Use default timezone (America/New_York)
uv run cli/mcp_client.py --url http://localhost/currenttime/mcp call \
	--tool current_time_by_timezone \
	--args '{}'
```

## Command Structure

### General Format
```bash
uv run cli/mcp_client.py [--url URL] COMMAND [--tool TOOL_NAME] [--args JSON_ARGS]
```

### Parameters
- `--url`: Gateway or server URL (default: `http://localhost/mcpgw/mcp`)
- `command`: One of `ping`, `list`, or `call`
- `--tool`: Tool name (required for `call` command)
- `--args`: Tool arguments as JSON string (for `call` command)

## Examples Summary

### Quick Server Management
```bash
# List all services
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call --tool list_services --args '{}'

# Register a new service
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool register_service \
	--args '{"server_name": "Minimal Server", "path": "/minimal-server", "proxy_pass_url": "http://minimal-server:8000"}'

# Remove a service
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool remove_service \
	--args '{"service_path": "/minimal-server"}'

# Toggle service state
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call \
	--tool toggle_service \
	--args '{"service_path": "/minimal-server"}'

# Health check all services
uv run cli/mcp_client.py --url http://localhost/mcpgw/mcp call --tool healthcheck --args '{}'
```

### Tool Discovery and Invocation
```bash
# Find relevant tools
uv run cli/mcp_client.py call --tool intelligent_tool_finder \
	--args '{"natural_language_query": "get current time"}'

# Call a specific tool directly
uv run cli/mcp_client.py --url http://localhost/currenttime/mcp call \
	--tool current_time_by_timezone \
	--args '{"tz_name": "Europe/London"}'
```

## Troubleshooting

### Common Issues

1. **HTTP 403: Access forbidden**
   - Check if your token has the required permissions
   - Verify the scopes.yml configuration includes the tool you're trying to access

2. **HTTP 405: Method Not Allowed**
   - Ensure the server path is correct
   - Verify the server is registered and running

3. **Token Expired**
   - Refresh your authentication token
   - For ingress tokens: Run the token refresh script
   - For M2M: Re-authenticate with credentials

4. **Connection Refused**
   - Check if the target server is running
   - Verify the proxy_pass_url in the service registration

## Notes

- All service paths must start with '/'
- Tool arguments must be valid JSON
- The gateway URL defaults to `http://localhost/mcpgw/mcp`
- Direct server access bypasses the gateway and connects directly to the service
