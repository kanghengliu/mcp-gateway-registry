import React, {useCallback, useEffect, useMemo, useRef, useState} from "react";
import {Box, Text, useInput} from "ink";
import TextInput from "ink-text-input";
import Spinner from "ink-spinner";

import {resolveAuth} from "./auth.js";
import type {ParsedArgs} from "./parseArgs.js";
import {executeSlashCommand, overviewMessage} from "./commands/executor.js";
import {runAgentTurn} from "./agent/agentRunner.js";
import type {AgentMessage} from "./agent/agentRunner.js";
import type {CommandExecutionContext} from "./commands/executor.js";
import {executeMcpCommand, formatMcpResult} from "./runtime/mcp.js";

type ChatRole = "system" | "user" | "assistant" | "tool";

interface ChatMessage {
  id: number;
  role: ChatRole;
  text: string;
}

interface AuthReadyState {
  status: "ready";
  context: Awaited<ReturnType<typeof resolveAuth>>;
}

type AuthState = {status: "loading"} | AuthReadyState | {status: "error"; message: string};

interface AppProps {
  options: ParsedArgs;
}

export default function App({options}: AppProps) {
  const interactive = options.interactive !== false;
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 0,
      role: "system",
      text: "Welcome to the MCP Registry chat CLI. Type /help to see what I can do."
    }
  ]);
  const messageCounter = useRef(1);
  const [inputValue, setInputValue] = useState("");
  const [authState, setAuthState] = useState<AuthState>({status: "loading"});
  const [authAttempt, setAuthAttempt] = useState(0);
  const [busy, setBusy] = useState(false);
  const [initialised, setInitialised] = useState(false);

  const gatewayUrl = useMemo(() => options.url ?? "http://localhost/mcpgw/mcp", [options.url]);
  const gatewayBaseUrl = useMemo(() => deriveGatewayBase(gatewayUrl), [gatewayUrl]);
  const agentAvailable = useMemo(() => Boolean(process.env.ANTHROPIC_API_KEY), []);

  const addMessage = useCallback((role: ChatRole, text: string) => {
    const id = messageCounter.current++;
    setMessages((prev) => [...prev, {id, role, text}]);
  }, []);

  useEffect(() => {
    let cancelled = false;
    setAuthState({status: "loading"});
    resolveAuth({
      tokenFile: options.tokenFile,
      explicitToken: options.token,
      cwd: process.cwd()
    })
      .then((context) => {
        if (!cancelled) {
          setAuthState({status: "ready", context});
        }
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setAuthState({status: "error", message: (error as Error).message});
        }
      });
    return () => {
      cancelled = true;
    };
  }, [options.token, options.tokenFile, authAttempt]);

  useEffect(() => {
    if (authState.status === "ready" && !initialised) {
      const infoLines = summariseAuth(authState, gatewayUrl);
      infoLines.forEach((line) => addMessage("assistant", line));
      setInitialised(true);
    }
  }, [authState, addMessage, initialised, gatewayUrl]);

  useEffect(() => {
    if (!interactive && authState.status === "ready" && options.command) {
      const command = options.command;
      (async () => {
        try {
          const extras = options.tool
            ? {
                tool: options.tool,
                args: options.args ? JSON.parse(options.args) : {}
              }
            : undefined;
          const result = await executeMcpCommand(
            command,
            gatewayUrl,
            authState.context.gatewayToken,
            authState.context.backendToken,
            extras
          );
          const lines = formatMcpResult(command, result.handshake, result.response, options.tool);
          // eslint-disable-next-line no-console
          console.log(options.json ? JSON.stringify({lines}) : lines.join("\n"));
          process.exit(0);
        } catch (error) {
          // eslint-disable-next-line no-console
          console.error((error as Error).message);
          process.exit(1);
        }
      })();
    }
  }, [authState, gatewayUrl, interactive, options]);

  useInput((input, key) => {
    if (key.ctrl && input === "c") {
      process.exit();
    }
  });

  const handleSubmit = useCallback(
    async (value: string) => {
      const trimmed = value.trim();
      if (!trimmed) {
        return;
      }

      setInputValue("");

      const userMessage: ChatMessage = {id: messageCounter.current++, role: "user", text: trimmed};
      setMessages((prev) => [...prev, userMessage]);

      if (trimmed === "/retry") {
        setAuthAttempt((attempt) => attempt + 1);
        setInitialised(false);
        addMessage("assistant", "Retrying authentication...");
        return;
      }

      if (authState.status !== "ready") {
        addMessage("assistant", "Authentication is not ready yet. Try /retry or wait a moment.");
        return;
      }

      const commandContext: CommandExecutionContext = {
        gatewayUrl,
        gatewayBaseUrl,
        gatewayToken: authState.context.gatewayToken,
        backendToken: authState.context.backendToken
      };

      const history: AgentMessage[] = buildAgentHistory([...messages, userMessage]);

      if (trimmed.startsWith("/")) {
        setBusy(true);
        try {
          const result = await executeSlashCommand(trimmed, commandContext);
          addMessage(result.isError ? "assistant" : "tool", result.lines.join("\n"));
        } catch (error) {
          addMessage("assistant", `Command failed: ${(error as Error).message}`);
        } finally {
          setBusy(false);
        }
        return;
      }

      if (!agentAvailable) {
        addMessage(
          "assistant",
          "Agent mode is disabled. Set ANTHROPIC_API_KEY to use natural language, or run slash commands like /ping."
        );
        return;
      }

      setBusy(true);
      try {
        const result = await runAgentTurn(history, {
          gatewayUrl,
          gatewayBaseUrl,
          gatewayToken: authState.context.gatewayToken,
          backendToken: authState.context.backendToken,
          model: process.env.ANTHROPIC_MODEL
        });

        result.toolOutputs.forEach((tool) => {
          const prefix = tool.isError ? `${tool.name} (error)` : tool.name;
          addMessage("tool", `${prefix} ->\n${tool.output}`);
        });

        if (result.messages.length === 0) {
          addMessage("assistant", "No response from the agent. Try a different prompt or use /help.");
        } else {
          result.messages.forEach((msg) => addMessage(msg.role, msg.content));
        }
      } catch (error) {
        addMessage("assistant", `Agent error: ${(error as Error).message}`);
      } finally {
        setBusy(false);
      }
    },
    [messages, authState, gatewayUrl, gatewayBaseUrl, agentAvailable, addMessage]
  );

  const renderMessages = () => (
    <Box flexDirection="column" gap={1}>
      {messages.map((message) => (
        <MessageBubble key={message.id} role={message.role} text={message.text} />
      ))}
    </Box>
  );

  const inputPrompt = useMemo(() => {
    if (busy) {
      return (
        <Text color="yellow">
          <Spinner type="dots" /> Working...
        </Text>
      );
    }
    if (authState.status === "loading") {
      return (
        <Text color="cyan">
          <Spinner type="dots" /> Authenticating...
        </Text>
      );
    }
    if (authState.status === "error") {
      return <Text color="red">Auth error. Type /retry once credentials are fixed.</Text>;
    }
    return <Text color="cyan">›</Text>;
  }, [authState, busy]);

  if (!interactive) {
    if (authState.status === "loading") {
      return (
        <Box>
          <Text>Authenticating...</Text>
        </Box>
      );
    }
    if (authState.status === "error") {
      return (
        <Box>
          <Text color="red">Authentication failed: {authState.message}</Text>
        </Box>
      );
    }
    return (
      <Box>
        <Text>Processing non-interactive command...</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" gap={1}>
      {renderMessages()}
      <Box>
        {inputPrompt}
        <Box marginLeft={1} flexGrow={1}>
          <TextInput
            value={inputValue}
            onChange={setInputValue}
            onSubmit={handleSubmit}
            placeholder="Type a message or use /commands"
          />
        </Box>
      </Box>
    </Box>
  );
}

function buildAgentHistory(messages: ChatMessage[]): AgentMessage[] {
  return messages
    .filter((message) => message.role !== "tool")
    .map((message) => ({
      role:
        message.role === "system"
          ? "system"
          : message.role === "assistant"
            ? "assistant"
            : "user",
      content: message.text
    }));
}

function summariseAuth(authState: AuthReadyState, gatewayUrl: string): string[] {
  const lines = [`Authenticated against ${gatewayUrl}`];
  const {context} = authState;
  if (context.gatewaySource && context.gatewaySource !== "none") {
    lines.push(`Gateway token source: ${context.gatewaySource}`);
  }
  if (context.backendSource && context.backendSource !== "none") {
    lines.push(`Backend token source: ${context.backendSource}`);
  }
  if (context.inspections.length > 0) {
    context.inspections.forEach((inspection) => {
      if (inspection.warning) {
        lines.push(`Token warning: ${inspection.warning}`);
      } else if (inspection.expiresAt) {
        lines.push(`${inspection.label} valid until ${inspection.expiresAt.toISOString()}`);
      }
    });
  }
  lines.push(overviewMessage());
  return lines;
}

interface MessageBubbleProps {
  role: ChatRole;
  text: string;
}

function MessageBubble({role, text}: MessageBubbleProps) {
  const color = roleColor(role);
  return (
    <Box flexDirection="column">
      <Text color={color}>
        {roleLabel(role)}: {text}
      </Text>
    </Box>
  );
}

function roleLabel(role: ChatRole): string {
  switch (role) {
    case "user":
      return "You";
    case "assistant":
      return "Assistant";
    case "tool":
      return "Tool";
    case "system":
    default:
      return "System";
  }
}

function roleColor(role: ChatRole): string | undefined {
  switch (role) {
    case "user":
      return "green";
    case "assistant":
      return "cyan";
    case "tool":
      return "yellow";
    case "system":
    default:
      return "magenta";
  }
}

function deriveGatewayBase(url: string): string {
  if (!url) {
    return "";
  }
  try {
    const parsed = new URL(url);
    const pathname = parsed.pathname.replace(/\/mcpgw\/mcp(?:\/.*)?$/, "");
    return `${parsed.origin}${pathname.endsWith("/") || pathname.length === 0 ? pathname : `${pathname}/`}`;
  } catch {
    return url.replace(/\/mcpgw\/mcp(?:\/.*)?$/, "");
  }
}
