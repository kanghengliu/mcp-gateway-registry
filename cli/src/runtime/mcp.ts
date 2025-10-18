import {McpClient} from "../client.js";
import type {CommandName} from "../parseArgs.js";
import type {JsonRpcResponse} from "../client.js";

export interface McpExecutionResult {
  handshake: JsonRpcResponse;
  response: JsonRpcResponse;
}

export async function executeMcpCommand(
  command: CommandName,
  gatewayUrl: string,
  gatewayToken?: string,
  backendToken?: string,
  callOptions?: {tool: string; args: Record<string, unknown>}
): Promise<McpExecutionResult> {
  const client = new McpClient({
    url: gatewayUrl,
    gatewayToken,
    backendToken
  });

  const handshake = await client.initialize();

  switch (command) {
    case "ping":
      return {handshake, response: await client.ping()};
    case "list":
      return {handshake, response: await client.listTools()};
    case "call": {
      if (!callOptions) {
        throw new Error("Tool name and args are required for /call.");
      }
      return {
        handshake,
        response: await client.callTool(callOptions.tool, callOptions.args)
      };
    }
    case "init":
    default:
      return {handshake, response: handshake};
  }
}

export function formatMcpResult(
  command: "ping" | "list" | "init" | "call",
  handshake: JsonRpcResponse,
  response: JsonRpcResponse,
  tool?: string
): string[] {
  const lines: string[] = [];
  const sessionId = (handshake as {result?: {sessionId?: string}}).result?.sessionId;
  if (sessionId) {
    lines.push(`Session established: ${sessionId}`);
  }
  if (command === "ping") {
    lines.push("Ping response:");
    lines.push(JSON.stringify(response, null, 2));
  } else if (command === "list") {
    lines.push("Available tools:");
    lines.push(JSON.stringify(response, null, 2));
  } else if (command === "call") {
    lines.push(`Tool "${tool}" response:`);
    lines.push(JSON.stringify(response, null, 2));
  } else if (command === "init") {
    lines.push("Initialization payload:");
    lines.push(JSON.stringify(handshake, null, 2));
  }
  return lines;
}
