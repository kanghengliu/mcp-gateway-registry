export interface McpClientOptions {
  url: string;
  gatewayToken?: string;
  backendToken?: string;
  timeout?: number;
}

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id?: number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse<T = unknown> {
  jsonrpc: "2.0";
  result?: T;
  error?: unknown;
  id?: number | string;
}

export type ToolArguments = Record<string, unknown>;

export class McpClient {
  private readonly url: string;
  private readonly gatewayToken?: string;
  private readonly backendToken?: string;
  private readonly timeout: number;
  private requestId = 0;
  private sessionId?: string;

  constructor(options: McpClientOptions) {
    this.url = options.url.replace(/\/$/, "");
    this.gatewayToken = options.gatewayToken;
    this.backendToken = options.backendToken;
    this.timeout = options.timeout ?? 30_000;
  }

  get currentSessionId(): string | undefined {
    return this.sessionId;
  }

  async initialize(): Promise<JsonRpcResponse> {
    const payload: JsonRpcRequest = {
      jsonrpc: "2.0",
      id: this.nextRequestId(),
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: {
          name: "mcp-ink-cli",
          version: "0.1.0"
        }
      }
    };

    const result = await this.execute(payload);
    await this.sendInitializedNotification();
    return result;
  }

  async ping(): Promise<JsonRpcResponse> {
    return this.execute({
      jsonrpc: "2.0",
      id: this.nextRequestId(),
      method: "ping"
    });
  }

  async listTools(): Promise<JsonRpcResponse> {
    return this.execute({
      jsonrpc: "2.0",
      id: this.nextRequestId(),
      method: "tools/list"
    });
  }

  async callTool(name: string, args: ToolArguments): Promise<JsonRpcResponse> {
    return this.execute({
      jsonrpc: "2.0",
      id: this.nextRequestId(),
      method: "tools/call",
      params: {
        name,
        arguments: args
      }
    });
  }

  private async sendInitializedNotification(): Promise<void> {
    try {
      await this.execute(
        {
          jsonrpc: "2.0",
          method: "notifications/initialized"
        },
        {ignoreErrors: true}
      );
    } catch {
      // Some servers respond with errors when notifications are not required; ignore them
    }
  }

  private nextRequestId(): number {
    this.requestId += 1;
    return this.requestId;
  }

  private async execute(payload: JsonRpcRequest, options?: {ignoreErrors?: boolean}): Promise<JsonRpcResponse> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeout);

    try {
      const response = await fetch(this.url, {
        method: "POST",
        headers: this.buildHeaders(),
        body: JSON.stringify(payload),
        signal: controller.signal
      });

      this.sessionId = response.headers.get("mcp-session-id") ?? this.sessionId;

      const contentType = response.headers.get("content-type") ?? "";
      const rawBody = await response.text();

      if (!response.ok && !options?.ignoreErrors) {
        throw buildHttpError(response.status, response.statusText, rawBody);
      }

      if (!rawBody) {
        return {jsonrpc: "2.0"};
      }

      if (contentType.includes("text/event-stream")) {
        return parseSsePayload(rawBody);
      }

      return JSON.parse(rawBody) as JsonRpcResponse;
    } catch (error) {
      if (options?.ignoreErrors) {
        return {jsonrpc: "2.0"};
      }

      if ((error as Error).name === "AbortError") {
        throw new Error(`Request to ${this.url} timed out after ${this.timeout} ms`);
      }

      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      "user-agent": "mcp-ink-cli/0.1.0"
    };

    if (this.gatewayToken) {
      headers["x-authorization"] = `Bearer ${this.gatewayToken}`;
    }

    if (this.backendToken) {
      headers.authorization = `Bearer ${this.backendToken}`;
    }

    if (this.sessionId) {
      headers["mcp-session-id"] = this.sessionId;
    }

    return headers;
  }

}

function buildHttpError(status: number, statusText: string, body: string): Error {
  try {
    const json = JSON.parse(body) as JsonRpcResponse & {error?: {message?: string}};
    if (json.error && typeof json.error === "object") {
      const message = (json.error as {message?: string}).message ?? JSON.stringify(json.error);
      return new Error(`HTTP ${status} ${statusText}: ${message}`);
    }
  } catch {
    // Ignore parse failures and fall back to raw body
  }
  const normalizedBody = body ? ` ${body.trim()}` : "";
  return new Error(`HTTP ${status} ${statusText}.${normalizedBody}`);
}

function parseSsePayload(raw: string): JsonRpcResponse {
  const lines = raw.split(/\r?\n/);
  for (const line of lines) {
    if (line.startsWith("data:")) {
      const payload = line.slice(5).trim();
      if (payload) {
        try {
          return JSON.parse(payload) as JsonRpcResponse;
        } catch {
          continue;
        }
      }
    }
  }

  return {
    jsonrpc: "2.0",
    error: {
      message: "No JSON payload found in SSE response"
    }
  };
}
