import {executeMcpCommand} from "../runtime/mcp.js";
import type {TaskContext} from "../tasks/types.js";
import {taskCatalog} from "../tasks/index.js";
import {executeSlashCommand} from "../commands/executor.js";

export interface AgentToolInvocation {
  type: "mcp" | "task" | "unknown";
  name: string;
  input: Record<string, unknown>;
}

export const anthropicTools: any[] = [
  {
    name: "mcp_command",
    description: "Call MCP gateway commands (ping, list, call, init).",
    input_schema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          enum: ["ping", "list", "call", "init"],
          description: "Which MCP command to execute."
        },
        tool: {
          type: "string",
          description: "Tool name for the call command"
        },
        args: {
          type: "object",
          description: "JSON arguments for the tool."
        }
      },
      required: ["command"]
    }
  },
  {
    name: "registry_task",
    description: "Run service management, imports, user management, or diagnostics tasks.",
    input_schema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "Slash command matching the CLI syntax, e.g. /service add configPath=..."
        }
      },
      required: ["command"]
    }
  }
];

export function mapToolCall(tool: any): AgentToolInvocation {
  if (tool.name === "mcp_command") {
    const input = tool.input as Record<string, unknown>;
    return {type: "mcp", name: tool.name, input};
  }
  if (tool.name === "registry_task") {
    const input = tool.input as Record<string, unknown>;
    return {type: "task", name: tool.name, input};
  }
  return {type: "unknown", name: tool.name, input: tool.input as Record<string, unknown>};
}

export async function executeMappedTool(
  invocation: AgentToolInvocation,
  gatewayUrl: string,
  context: TaskContext
): Promise<{output: string; isError?: boolean}> {
  if (invocation.type === "mcp") {
    const command = String(invocation.input.command || "");
    if (!command) {
      return {output: "Missing command field", isError: true};
    }
    const toolName = invocation.input.tool ? String(invocation.input.tool) : undefined;
    const args = invocation.input.args && typeof invocation.input.args === "object" ? (invocation.input.args as Record<string, unknown>) : {};
    try {
      const {handshake, response} = await executeMcpCommand(command as any, gatewayUrl, context.gatewayToken, context.backendToken, toolName ? {tool: toolName, args} : undefined);
      return {output: JSON.stringify({handshake, response}, null, 2)};
    } catch (error) {
      return {output: (error as Error).message, isError: true};
    }
  }

  if (invocation.type === "task") {
    let commandText = String(invocation.input.command || "").trim();
    if (!commandText.startsWith("/")) {
      commandText = `/${commandText}`;
    }
    const result = await executeSlashCommand(commandText, context);
    return {output: result.lines.join("\n"), isError: result.isError};
  }

  return {output: `Unknown tool invocation: ${invocation.name}`, isError: true};
}

export function buildTaskContext(gatewayUrl: string, baseUrl: string, gatewayToken?: string, backendToken?: string): TaskContext {
  return {
    gatewayUrl,
    gatewayBaseUrl: baseUrl,
    gatewayToken,
    backendToken
  };
}

export function describeAvailableTasks(): string {
  const lines: string[] = [];
  for (const [category, tasks] of Object.entries(taskCatalog)) {
    lines.push(`Category: ${category}`);
    tasks.forEach((task) => {
      lines.push(`  - ${task.key.replace(`${category}-`, "")}: ${task.description ?? ""}`);
    });
  }
  return lines.join("\n");
}
