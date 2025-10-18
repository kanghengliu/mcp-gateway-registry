import { getAnthropicClient } from "./anthropicClient.js";
import { anthropicTools, buildTaskContext, executeMappedTool, mapToolCall } from "./tools.js";
import type { TaskContext } from "../tasks/types.js";

export interface AgentMessage {
  role: "user" | "assistant" | "system";
  content: string;
}

export interface AgentConfig {
  gatewayUrl: string;
  gatewayBaseUrl: string;
  gatewayToken?: string;
  backendToken?: string;
  model?: string;
}

export interface AgentResult {
  messages: AgentMessage[];
  toolOutputs: Array<{ name: string; output: string; isError?: boolean }>;
}

const DEFAULT_MODEL = process.env.ANTHROPIC_MODEL ?? "claude-haiku-4-5";

type ConversationEntry = {
  role: string;
  content: any;
  tool_use_id?: string;
};

export async function runAgentTurn(history: AgentMessage[], config: AgentConfig): Promise<AgentResult> {
  const client = getAnthropicClient();

  const systemMessages = history.filter((msg) => msg.role === "system").map((msg) => msg.content);
  const systemPrompt = [buildSystemPrompt(), ...systemMessages].join("\n\n");

  const messages = history
    .filter((msg) => msg.role === "user" || msg.role === "assistant")
    .map((msg) => ({ role: msg.role, content: msg.content })) as ConversationEntry[];

  const context: TaskContext = buildTaskContext(config.gatewayUrl, config.gatewayBaseUrl, config.gatewayToken, config.backendToken);

  const finalMessages: AgentMessage[] = [];
  const toolOutputs: Array<{ name: string; output: string; isError?: boolean }> = [];

  let toolIteration = 0;
  let conversation: ConversationEntry[] = [...messages];
  if (conversation.length === 0) {
    conversation.push({ role: "user", content: history.filter((msg) => msg.role !== "system").map((msg) => msg.content).join("\n") || "Hello." });
  }

  while (toolIteration < 5) {
    const response = await (client as any).beta.tools.messages.create({
      model: config.model ?? DEFAULT_MODEL,
      system: systemPrompt,
      messages: conversation,
      max_tokens: 1024,
      tools: anthropicTools
    });

    const outputBlocks = (response.content ?? []) as any[];
    const toolCalls = outputBlocks.filter((block) => block.type === "tool_use");
    const textBlocks = outputBlocks.filter((block) => block.type === "text");

    if (toolCalls.length === 0) {
      const content = textBlocks.map((block) => (block.type === "text" ? block.text : "")).join("\n");
      finalMessages.push({ role: "assistant", content });
      break;
    }

    const assistantMessage: ConversationEntry = { role: "assistant", content: response.content };
    conversation = [...conversation, assistantMessage];

    for (const call of toolCalls) {
      const invocation = mapToolCall(call);
      const result = await executeMappedTool(invocation, config.gatewayUrl, context);
      toolOutputs.push({ name: call.name, output: result.output, isError: result.isError });
      conversation = [
        ...conversation,
        {
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: call.id,
              content: result.output
            }
          ]
        }
      ];
    }

    toolIteration += 1;
  }

  if (toolIteration >= 5) {
    finalMessages.push({ role: "assistant", content: "Reached tool usage limit without final response." });
  }

  return { messages: finalMessages, toolOutputs };
}

function buildSystemPrompt(): string {
  return `You are an MCP Registry assistant with direct access to CLI tools.

Tools available:
- mcp_command: call MCP gateway commands (ping, list, call, init)
- registry_task: invoke service management, imports, user management, diagnostics via slash commands.

Behaviours:
- Use tools whenever the user asks for an action.
- Always prefer precise tool usage with correct parameters.
- Summarise results for the user after tool invocations.
- Never expose secrets or raw environment details.`;
}
