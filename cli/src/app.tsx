import React, {useEffect, useMemo, useState} from "react";
import {Box, Text, useApp, useInput} from "ink";
import Spinner from "ink-spinner";
import SelectInput from "ink-select-input";
import {z} from "zod";

import type {CommandName, ParsedArgs} from "./parseArgs.js";
import {resolveAuth, type AuthContext} from "./auth.js";
import {McpClient, type JsonRpcResponse, type ToolArguments} from "./client.js";
import {Banner} from "./components/Banner.js";
import {CallToolForm} from "./components/CallToolForm.js";
import {JsonViewer} from "./components/JsonViewer.js";
import {StatusMessage} from "./components/StatusMessage.js";
import {UrlEditor} from "./components/UrlEditor.js";
import {TokenFileEditor} from "./components/TokenFileEditor.js";
import {MultiStepForm} from "./components/MultiStepForm.js";
import {TaskRunner} from "./components/TaskRunner.js";
import {taskCatalog, getTaskByKey, resolveDefaultValues} from "./tasks/index.js";
import type {ScriptCommand, ScriptTask, TaskCategory} from "./tasks/types.js";

type View =
  | "loading"
  | "menu"
  | "category-menu"
  | "executing"
  | "result"
  | "error"
  | "call-form"
  | "url-edit"
  | "token-edit"
  | "script-form"
  | "script-task";

interface CommandResult {
  command: CommandName;
  handshake: JsonRpcResponse;
  response?: JsonRpcResponse;
  executedAt: Date;
}

type AuthState =
  | {status: "loading"}
  | {status: "ready"; context: AuthContext}
  | {status: "error"; message: string};

type MenuValue =
  | {type: "command"; command: CommandName}
  | {type: "call"}
  | {type: "edit-url"}
  | {type: "edit-token"}
  | {type: "reload-auth"}
  | {type: "category"; category: TaskCategory}
  | {type: "quit"};

const argsSchema = z.record(z.any());
const DEFAULT_URL = process.env.MCP_URL ?? "http://localhost/mcpgw/mcp";
const CATEGORY_LABELS: Record<TaskCategory, string> = {
  service: "Gateway Service Toolkit",
  import: "Registry Imports",
  user: "User & M2M Management",
  diagnostic: "API Diagnostics"
};

interface AppProps {
  options: ParsedArgs;
}

export default function App({options}: AppProps) {
  const {exit} = useApp();

  const [url, setUrl] = useState(options.url ?? DEFAULT_URL);
  const [tokenFile, setTokenFile] = useState(options.tokenFile);
  const [authState, setAuthState] = useState<AuthState>({status: "loading"});
  const [authReloadKey, setAuthReloadKey] = useState(0);
  const [view, setView] = useState<View>("loading");
  const [result, setResult] = useState<CommandResult | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [executing, setExecuting] = useState(false);
  const [callDefaults, setCallDefaults] = useState<{tool?: string; args?: string}>({
    tool: options.tool,
    args: options.args
  });
  const [activeCategory, setActiveCategory] = useState<TaskCategory | null>(null);
  const [pendingScriptTask, setPendingScriptTask] = useState<{task: ScriptTask; category: TaskCategory} | null>(null);
  const [runningScriptTask, setRunningScriptTask] = useState<{task: ScriptTask; category: TaskCategory; command: ScriptCommand} | null>(null);

  const interactive = options.interactive !== false;
  const gatewayBaseUrl = useMemo(() => deriveGatewayBase(url), [url]);
  const taskContext = useMemo(
    () => ({
      gatewayUrl: url,
      gatewayBaseUrl
    }),
    [url, gatewayBaseUrl]
  );

  useEffect(() => {
    let cancelled = false;
    setAuthState({status: "loading"});

    resolveAuth({
      tokenFile,
      explicitToken: options.token,
      cwd: process.cwd()
    })
      .then((context) => {
        if (!cancelled) {
          setAuthState({status: "ready", context});
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setAuthState({status: "error", message: (err as Error).message});
        }
      });

    return () => {
      cancelled = true;
    };
  }, [tokenFile, options.token, authReloadKey]);

  useEffect(() => {
    if (authState.status === "ready") {
      if (!interactive && options.command) {
        void executeCommand(options.command, {
          tool: options.tool,
          args: options.args
        });
      } else if (view === "loading") {
        setView("menu");
      }
    }
  }, [authState, interactive, options.command, options.tool, options.args, view]);

  useInput((input, key) => {
    if (!interactive) {
      if (key.ctrl && input === "c") {
        exit();
      }
      return;
    }

    if (key.ctrl && input === "c") {
      exit();
    }

    if (view === "script-task" || view === "script-form") {
      return;
    }

    if (view === "category-menu") {
      if (input === "q") {
        setActiveCategory(null);
        setPendingScriptTask(null);
        setRunningScriptTask(null);
        setView("menu");
      }
      return;
    }

    if (view === "menu") {
      if (input === "q") {
        exit();
      }
    } else if (view === "result") {
      if (key.return) {
        setView("menu");
      }
      if (input === "q") {
        exit();
      }
    } else if (view === "error") {
      if (key.return) {
        setView("menu");
        setError(undefined);
      }
    }
  });

  const authSummary = useMemo(() => {
    if (authState.status !== "ready") {
      return undefined;
    }

    const {backendSource, gatewaySource, tokenFile: tf} = authState.context;

    const backendLabel = (() => {
      switch (backendSource) {
        case "token-file":
          return tf ? `token file (${tf})` : "token file";
        case "m2m":
          return "Keycloak M2M credentials";
        case "explicit":
          return "explicit token";
        default:
          return "none";
      }
    })();

    const gatewayLabel = (() => {
      switch (gatewaySource) {
        case "env":
          return "environment token";
        case "ingress-json":
          return ".oauth-tokens/ingress.json";
        case "token-file":
          return "~/.mcp/ingress_token";
        default:
          return "none";
      }
    })();

    return {backendLabel, gatewayLabel};
  }, [authState]);

  const menuItems = useMemo(() => {
    const items: Array<{key: string; label: string; value: MenuValue}> = [
      {key: "ping", label: "Ping gateway", value: {type: "command", command: "ping"}},
      {key: "list", label: "List tools", value: {type: "command", command: "list"}},
      {key: "call", label: "Call a tool...", value: {type: "call"}},
      {key: "init", label: "Initialize session", value: {type: "command", command: "init"}},
      {key: "service-toolkit", label: "Gateway service toolkit", value: {type: "category", category: "service"}},
      {key: "registry-imports", label: "Registry imports", value: {type: "category", category: "import"}},
      {key: "user-management", label: "User & M2M management", value: {type: "category", category: "user"}},
      {key: "api-diagnostics", label: "API diagnostics", value: {type: "category", category: "diagnostic"}},
      {key: "edit-url", label: "Change gateway URL", value: {type: "edit-url"}},
      {key: "edit-token", label: "Update token file", value: {type: "edit-token"}},
      {key: "reload-auth", label: "Reload authentication", value: {type: "reload-auth"}},
      {key: "quit", label: "Quit", value: {type: "quit"}}
    ];

    return items;
  }, []);

  const isReady = authState.status === "ready";

  if (options.helpRequested) {
    return (
      <Box flexDirection="column">
        <Text>Run with --help from the wrapper to view usage.</Text>
      </Box>
    );
  }

  if (authState.status === "loading") {
    return (
      <Box flexDirection="column" gap={1}>
        <Text>
          <Text color="cyan">
            <Spinner type="dots" />
          </Text>{" "}
          Detecting authentication...
        </Text>
      </Box>
    );
  }

  if (authState.status === "error") {
    return (
      <Box flexDirection="column" gap={1}>
        <Text color="red">Authentication error: {authState.message}</Text>
      </Box>
    );
  }

  const authWarnings = authState.context.warnings;

  const inspections = authState.context.inspections;

  const header = (
    <Box flexDirection="column" gap={1}>
      <Banner />
      <Text>
        Gateway URL: <Text color="green">{url}</Text>
      </Text>
      <Text>
        Gateway auth: <Text color="green">{authSummary?.gatewayLabel ?? "n/a"}</Text>
      </Text>
      <Text>
        Backend auth: <Text color="green">{authSummary?.backendLabel ?? "n/a"}</Text>
      </Text>
      {tokenFile ? <Text dimColor>Token file: {tokenFile}</Text> : null}
      {inspections.map((inspection) => (
        <Text key={inspection.label} dimColor>
          {inspection.label}
          {inspection.expiresAt
            ? ` expires ${inspection.expired ? "in the past" : `at ${inspection.expiresAt.toISOString()}`}`
            : ""}
          {inspection.warning ? ` — ${inspection.warning}` : ""}
        </Text>
      ))}
      {authWarnings.map((warning) => (
        <StatusMessage key={warning} variant="warning" message={warning} />
      ))}
    </Box>
  );

  if (!interactive && options.command && executing) {
    return null;
  }

  const renderMenu = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <Text dimColor>Select an action:</Text>
      <SelectInput
        items={menuItems}
        onSelect={(item) => handleMenuSelect(item.value)}
        itemComponent={MenuItem}
      />
      <Text dimColor>Use ↑ ↓ to navigate, ↵ to confirm, q to quit.</Text>
    </Box>
  );

  const renderCallForm = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <CallToolForm
        initialTool={callDefaults.tool}
        initialArgs={callDefaults.args}
        onSubmit={({tool, args}) => {
          setCallDefaults({tool, args});
          void executeCommand("call", {tool, args});
        }}
        onCancel={() => setView("menu")}
      />
    </Box>
  );

  const renderUrlEditor = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <UrlEditor
        initialUrl={url}
        onSubmit={(value) => {
          setUrl(value);
          setView("menu");
        }}
        onCancel={() => setView("menu")}
      />
    </Box>
  );

  const renderTokenEditor = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <TokenFileEditor
        initialPath={tokenFile}
        onSubmit={(value) => {
          setTokenFile(value);
          setAuthReloadKey((key) => key + 1);
          setView("menu");
        }}
        onCancel={() => setView("menu")}
      />
    </Box>
  );

  const renderCategoryMenu = (category: TaskCategory) => {
    const tasks = taskCatalog[category];
    type CategoryMenuValue = {type: "task"; taskKey: string} | {type: "back"};
    const items: Array<{key: string; label: string; value: CategoryMenuValue}> = tasks.map((task) => ({
      key: task.key,
      label: task.label,
      value: {type: "task", taskKey: task.key}
    }));
    items.push({key: "back", label: "Back to main menu", value: {type: "back"}});

    return (
      <Box flexDirection="column" gap={1}>
        {header}
        <Text>
          <Text bold>{CATEGORY_LABELS[category]}</Text>
        </Text>
        {tasks.length === 0 ? <Text dimColor>No tasks available.</Text> : null}
        <SelectInput
          items={items}
          onSelect={(item) => handleCategoryMenuSelect(category, item.value)}
          itemComponent={MenuItem}
        />
        <Text dimColor>Use ↑ ↓ to pick a task, ↵ to confirm, q to return.</Text>
      </Box>
    );
  };

  const renderScriptForm = () => {
    if (!pendingScriptTask) {
      return null;
    }
    const {task} = pendingScriptTask;
    return (
      <Box flexDirection="column" gap={1}>
        {header}
        <MultiStepForm
          key={task.key}
          heading={task.label}
          fields={task.fields}
          initialValues={resolveDefaultValues(task)}
          onSubmit={handleScriptFormSubmit}
          onCancel={() => {
            setPendingScriptTask(null);
            setView("category-menu");
          }}
        />
      </Box>
    );
  };

  const renderScriptTask = () => {
    if (!runningScriptTask) {
      return null;
    }
    return (
      <Box flexDirection="column" gap={1}>
        {header}
        <TaskRunner
          title={runningScriptTask.task.label}
          description={runningScriptTask.task.description}
          command={runningScriptTask.command}
          onDone={() => {
            setRunningScriptTask(null);
            setView(activeCategory ? "category-menu" : "menu");
          }}
        />
      </Box>
    );
  };

  const renderExecuting = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <Text>
        <Text color="cyan">
          <Spinner type="dots" />
        </Text>{" "}
        Working...
      </Text>
    </Box>
  );

  const renderResult = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      {result ? (
        <Box flexDirection="column" gap={1}>
          <StatusMessage variant="info" message={`Command ${result.command} completed at ${result.executedAt.toISOString()}`} />
          <JsonViewer label="Initialize" data={result.handshake} raw={options.json} />
          {result.command !== "init" && result.response ? (
            <JsonViewer label="Response" data={result.response} raw={options.json} />
          ) : null}
          {interactive ? <Text dimColor>Press ↵ to return to the menu or q to quit.</Text> : null}
        </Box>
      ) : (
        <StatusMessage variant="warning" message="No result to display." />
      )}
    </Box>
  );

  const renderError = () => (
    <Box flexDirection="column" gap={1}>
      {header}
      <StatusMessage variant="error" message={error ?? "Unknown error"} />
      {interactive ? <Text dimColor>Press ↵ to return to the menu.</Text> : null}
    </Box>
  );

  if (!interactive && result && !executing) {
    // Non-interactive mode prints plain JSON for scripts
    const payload = {
      command: result.command,
      executedAt: result.executedAt.toISOString(),
      initialize: result.handshake,
      response: result.response
    };
    // eslint-disable-next-line no-console
    console.log(options.json ? JSON.stringify(payload) : JSON.stringify(payload, null, 2));
    exit();
    return null;
  }

  if (!interactive && error && !executing) {
    // eslint-disable-next-line no-console
    console.error(error);
    process.exit(1);
    return null;
  }

  if (!isReady) {
    return renderExecuting();
  }

  switch (view) {
    case "menu":
      return renderMenu();
    case "category-menu":
      return activeCategory ? renderCategoryMenu(activeCategory) : renderMenu();
    case "call-form":
      return renderCallForm();
    case "url-edit":
      return renderUrlEditor();
    case "token-edit":
      return renderTokenEditor();
    case "script-form":
      return renderScriptForm();
    case "script-task":
      return renderScriptTask();
    case "executing":
      return renderExecuting();
    case "result":
      return renderResult();
    case "error":
      return renderError();
    default:
      return renderExecuting();
  }

  async function executeCommand(command: CommandName, extras?: {tool?: string; args?: string}) {
    if (authState.status !== "ready") {
      return;
    }

    if (command === "call") {
      const tool = extras?.tool?.trim();
      if (!tool) {
        setError("A tool name is required for the call command.");
        setView("error");
        return;
      }
    }

    const argsObj = (() => {
      if (command !== "call") {
        return undefined;
      }

      try {
        return parseToolArguments(extras?.args);
      } catch (parseError) {
        setError((parseError as Error).message);
        setView("error");
        return undefined;
      }
    })();

    if (command === "call" && argsObj === undefined) {
      return;
    }

    setExecuting(true);
    setError(undefined);
    setView(interactive ? "executing" : "result");

    try {
      const client = new McpClient({
        url,
        gatewayToken: authState.context.gatewayToken,
        backendToken: authState.context.backendToken
      });

      const handshake = await client.initialize();
      let response: JsonRpcResponse | undefined;

      switch (command) {
        case "ping":
          response = await client.ping();
          break;
        case "list":
          response = await client.listTools();
          break;
        case "call":
          response = await client.callTool(extras?.tool ?? "", argsObj as ToolArguments);
          break;
        case "init":
          response = handshake;
          break;
      }

      setResult({
        command,
        handshake,
        response,
        executedAt: new Date()
      });
      setView("result");
    } catch (err) {
      setError((err as Error).message);
      setView("error");
    } finally {
      setExecuting(false);
    }
  }

  function handleCategoryMenuSelect(
    category: TaskCategory,
    value: {type: "task"; taskKey: string} | {type: "back"}
  ) {
    if (value.type === "back") {
      setActiveCategory(null);
      setPendingScriptTask(null);
      setRunningScriptTask(null);
      setView("menu");
      return;
    }

    const task = getTaskByKey(category, value.taskKey);
    if (!task) {
      return;
    }

    if (task.fields.length === 0) {
      try {
        const command = task.build({}, taskContext);
        setRunningScriptTask({task, category, command});
        setPendingScriptTask(null);
        setView("script-task");
      } catch (err) {
        setError((err as Error).message);
        setView("error");
      }
      return;
    }

    setPendingScriptTask({task, category});
    setView("script-form");
  }

  function handleScriptFormSubmit(values: Record<string, string>) {
    if (!pendingScriptTask) {
      return;
    }

    const {task, category} = pendingScriptTask;
    try {
      const command = task.build(values, taskContext);
      setRunningScriptTask({task, category, command});
      setPendingScriptTask(null);
      setView("script-task");
    } catch (err) {
      setError((err as Error).message);
      setView("error");
    }
  }

  function handleMenuSelect(value: MenuValue) {
    switch (value.type) {
      case "command":
        void executeCommand(value.command);
        break;
      case "call":
        setView("call-form");
        break;
      case "edit-url":
        setView("url-edit");
        break;
      case "edit-token":
        setView("token-edit");
        break;
      case "reload-auth":
        setAuthReloadKey((key) => key + 1);
        break;
      case "category":
        setActiveCategory(value.category);
        setPendingScriptTask(null);
        setRunningScriptTask(null);
        setView("category-menu");
        break;
      case "quit":
        exit();
        break;
    }
  }
}

function parseToolArguments(raw?: string): ToolArguments {
  if (!raw || raw.trim().length === 0) {
    return {};
  }

  try {
    const parsed = JSON.parse(raw);
    return argsSchema.parse(parsed);
  } catch (error) {
    throw new Error(`Invalid JSON for --args: ${(error as Error).message}`);
  }
}

function MenuItem({isSelected, label}: {isSelected?: boolean; label: string}) {
  if (isSelected) {
    return <Text color="green">› {label}</Text>;
  }
  return <Text>  {label}</Text>;
}

function deriveGatewayBase(url: string): string {
  if (!url) {
    return "";
  }
  try {
    const parsed = new URL(url);
    let pathname = parsed.pathname.replace(/\/mcpgw\/mcp(?:\/.*)?$/, "");
    if (pathname === "/") {
      pathname = "";
    }
    return `${parsed.origin}${pathname}`;
  } catch {
    return url.replace(/\/mcpgw\/mcp(?:\/.*)?$/, "");
  }
}
