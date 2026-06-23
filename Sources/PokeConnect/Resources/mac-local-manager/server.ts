import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import { exec, execFile } from "child_process";
import { promisify } from "util";
import fs from "fs/promises";
import path from "path";
import os from "os";

const execAsync = promisify(exec);
const execFileAsync = promisify(execFile);
const app = express();
const publicDirectory = "/tmp";
const dashboardPath = path.join(publicDirectory, "dashboard.json");
const dashboardLogLimit = 80;

// Serve dashboard files from /tmp under the /public route.
app.use('/public', express.static(publicDirectory));

type AgentStatus = "idle" | "running" | "completed" | "blocked" | "error";

type AgentState = {
  id: string;
  name: string;
  status: AgentStatus;
  progress: number;
  calls: number;
  errors: number;
  active: number;
  lastEvent: string;
  startedAt?: string;
  updatedAt: string;
};

const tracker: {
  startedAt: string;
  bridge: {
    status: "starting" | "connected" | "disconnected";
    transport: "none" | "sse";
    activeCalls: number;
    totalCalls: number;
  };
  agents: Record<string, AgentState>;
  logs: string[];
} = {
  startedAt: new Date().toISOString(),
  bridge: {
    status: "starting",
    transport: "none",
    activeCalls: 0,
    totalCalls: 0,
  },
  agents: {},
  logs: [],
};

function nowISO(): string {
  return new Date().toISOString();
}

function appendTrackerLog(message: string) {
  const time = new Date().toLocaleTimeString("en-US", { hour12: false });
  tracker.logs.push(`[${time}] ${message}`);
  if (tracker.logs.length > dashboardLogLimit) {
    tracker.logs.splice(0, tracker.logs.length - dashboardLogLimit);
  }
}

function getAgent(name: string): AgentState {
  const id = name.replace(/[^a-z0-9_-]/gi, "_").toLowerCase();
  tracker.agents[id] ||= {
    id,
    name,
    status: "idle",
    progress: 0,
    calls: 0,
    errors: 0,
    active: 0,
    lastEvent: "Waiting for Poke",
    updatedAt: nowISO(),
  };
  return tracker.agents[id];
}

function writeDashboard() {
  fs.writeFile(dashboardPath, JSON.stringify(dashboardPayload(), null, 2)).catch((error) => {
    console.error("Unable to write dashboard state:", error);
  });
}

function dashboardPayload() {
  const agents = Object.values(tracker.agents)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  return {
    updatedAt: nowISO(),
    startedAt: tracker.startedAt,
    bridge: tracker.bridge,
    agents,
    logs: tracker.logs,
  };
}

function markBridge(status: typeof tracker.bridge.status, event: string) {
  tracker.bridge.status = status;
  tracker.bridge.transport = status === "connected" ? "sse" : "none";
  appendTrackerLog(event);
  writeDashboard();
}

function startToolCall(name: string) {
  const agent = getAgent(name);
  const updatedAt = nowISO();
  agent.status = "running";
  agent.progress = 50;
  agent.calls += 1;
  agent.active += 1;
  agent.startedAt = updatedAt;
  agent.updatedAt = updatedAt;
  agent.lastEvent = "Poke requested this tool";
  tracker.bridge.activeCalls += 1;
  tracker.bridge.totalCalls += 1;
  appendTrackerLog(`Poke started ${name}`);
  writeDashboard();
}

function finishToolCall(name: string, error?: string) {
  const agent = getAgent(name);
  agent.active = Math.max(0, agent.active - 1);
  agent.progress = 100;
  agent.status = error ? "error" : "completed";
  agent.errors += error ? 1 : 0;
  agent.lastEvent = error ? error : "Completed successfully";
  agent.updatedAt = nowISO();
  tracker.bridge.activeCalls = Math.max(0, tracker.bridge.activeCalls - 1);
  appendTrackerLog(error ? `Poke ${name} failed: ${error}` : `Poke completed ${name}`);
  writeDashboard();
}

function createServer() {
  const server = new Server(
    {
      name: "mac-local-manager",
      version: "1.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

// Safety gate logic
const DESTRUCTIVE_KEYWORDS = ["rm", "mv", "delete", "remove", "kill", "format", "chmod", "chown", "sudo"];

function isDestructive(command: string): boolean {
  const lower = command.toLowerCase();
  return DESTRUCTIVE_KEYWORDS.some(keyword => new RegExp(`(^|[^a-z0-9_])${keyword}($|[^a-z0-9_])`).test(lower));
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  appendTrackerLog("Poke requested available tools");
  writeDashboard();
  return {
    tools: [
      {
        name: "read_file",
        description: "Read the contents of a file on the Mac",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
          },
          required: ["path"],
        },
      },
      {
        name: "write_file",
        description: "Write content to a file on the Mac (Approval gated for config/system files)",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
            content: { type: "string" },
          },
          required: ["path", "content"],
        },
      },
      {
        name: "list_directory",
        description: "List files and directories",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
          },
          required: ["path"],
        },
      },
      {
        name: "run_command",
        description: "Run a terminal command (Approval gated for destructive actions)",
        inputSchema: {
          type: "object",
          properties: {
            command: { type: "string" },
          },
          required: ["command"],
        },
      },
      {
        name: "inspect_processes",
        description: "List currently running processes",
        inputSchema: {
          type: "object",
        },
      },
      {
        name: "capture_screenshot",
        description: "Take a screenshot of the Mac screen",
        inputSchema: {
          type: "object",
          properties: {
            output_path: { type: "string", description: "Where to save the screenshot" },
          },
        },
      },
    ],
  };
});

app.get("/public/tracker-state", (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json(dashboardPayload());
});

function screenshotPathFromCommand(command: string): string {
  const match = command.match(/screencapture(?:\s+-\S+)*\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
  return match?.[1]?.replace(/^['"]|['"]$/g, "") || path.join(os.tmpdir(), `screenshot_${Date.now()}.png`);
}

async function captureScreenshot(outputPath: string) {
  await execFileAsync("screencapture", ["-x", outputPath]);
  const data = await fs.readFile(outputPath, "base64");
  return {
    content: [
      { type: "text" as const, text: `Screenshot saved to: ${outputPath}` },
      { type: "image" as const, data, mimeType: "image/png" },
    ],
  };
}

async function runTool(name: string, args: any) {
  switch (name) {
    case "read_file": {
      const filePath = path.resolve(args?.path as string);
      const data = await fs.readFile(filePath, "utf-8");
      return { content: [{ type: "text" as const, text: data }] };
    }

    case "write_file": {
      const filePath = path.resolve(args?.path as string);
      const content = args?.content as string;

      const sensitivePaths = ["/etc", "/var", "/Library", "/System", ".bashrc", ".zshrc", ".ssh"];
      if (sensitivePaths.some(p => filePath.includes(p))) {
        return {
          content: [{ type: "text" as const, text: `APPROVAL_NEEDED: Writing to a sensitive path: ${filePath}` }],
          isError: true,
        };
      }

      await fs.writeFile(filePath, content);
      return { content: [{ type: "text" as const, text: `Successfully wrote to ${filePath}` }] };
    }

    case "list_directory": {
      const dirPath = path.resolve(args?.path as string || ".");
      const files = await fs.readdir(dirPath);
      return { content: [{ type: "text" as const, text: files.join("\n") }] };
    }

    case "run_command": {
      const command = args?.command as string;
      if (command.includes("screencapture")) {
        return captureScreenshot(screenshotPathFromCommand(command));
      }
      if (isDestructive(command)) {
        return {
          content: [{ type: "text" as const, text: `APPROVAL_NEEDED: Destructive command detected: ${command}` }],
          isError: true,
        };
      }
      const { stdout, stderr } = await execAsync(command);
      return { content: [{ type: "text" as const, text: stdout || stderr }] };
    }

    case "inspect_processes": {
      const { stdout } = await execAsync("ps aux");
      return { content: [{ type: "text" as const, text: stdout }] };
    }

    case "capture_screenshot": {
      const outputPath = (args?.output_path as string) || path.join(os.tmpdir(), `screenshot_${Date.now()}.png`);
      return captureScreenshot(outputPath);
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  startToolCall(name);

  try {
    const result = await runTool(name, args);
    finishToolCall(name, (result as any).isError ? result.content[0]?.text : undefined);
    return result;
  } catch (error: any) {
    finishToolCall(name, error.message);
    return {
      content: [{ type: "text", text: error.message }],
      isError: true,
    };
  }
});

  return server;
}

const transports = new Map<string, SSEServerTransport>();

app.get("/sse", async (req, res) => {
  const server = createServer();
  const transport = new SSEServerTransport("/messages", res);
  transports.set(transport.sessionId, transport);
  markBridge("connected", "Poke connected over SSE");
  transport.onclose = () => {
    transports.delete(transport.sessionId);
    markBridge("disconnected", "Poke SSE connection closed");
  };
  await server.connect(transport);
});

app.post("/messages", async (req, res) => {
  const sessionId = req.query.sessionId as string;
  const transport = transports.get(sessionId);
  if (transport) {
    await transport.handlePostMessage(req, res);
  } else {
    res.status(400).send("SSE connection not established");
  }
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`mac-local-manager running on http://localhost:${PORT}`);
  markBridge("disconnected", `mac-local-manager listening on port ${PORT}`);
});
