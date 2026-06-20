import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import { exec } from "child_process";
import { promisify } from "util";
import fs from "fs/promises";
import path from "path";
import os from "os";

const execAsync = promisify(exec);
const app = express();

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
  return DESTRUCTIVE_KEYWORDS.some(keyword => lower.includes(keyword));
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
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

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "read_file": {
        const filePath = path.resolve(args?.path as string);
        const data = await fs.readFile(filePath, "utf-8");
        return { content: [{ type: "text", text: data }] };
      }

      case "write_file": {
        const filePath = path.resolve(args?.path as string);
        const content = args?.content as string;

        const sensitivePaths = ["/etc", "/var", "/Library", "/System", ".bashrc", ".zshrc", ".ssh"];
        if (sensitivePaths.some(p => filePath.includes(p))) {
          return {
            content: [{ type: "text", text: `APPROVAL_NEEDED: Writing to a sensitive path: ${filePath}` }],
            isError: true,
          };
        }

        await fs.writeFile(filePath, content);
        return { content: [{ type: "text", text: `Successfully wrote to ${filePath}` }] };
      }

      case "list_directory": {
        const dirPath = path.resolve(args?.path as string || ".");
        const files = await fs.readdir(dirPath);
        return { content: [{ type: "text", text: files.join("\n") }] };
      }

      case "run_command": {
        const command = args?.command as string;
        if (isDestructive(command)) {
          return {
            content: [{ type: "text", text: `APPROVAL_NEEDED: Destructive command detected: ${command}` }],
            isError: true,
          };
        }
        const { stdout, stderr } = await execAsync(command);
        return { content: [{ type: "text", text: stdout || stderr }] };
      }

      case "inspect_processes": {
        const { stdout } = await execAsync("ps aux");
        return { content: [{ type: "text", text: stdout }] };
      }

      case "capture_screenshot": {
        const outputPath = (args?.output_path as string) || path.join(os.tmpdir(), `screenshot_${Date.now()}.png`);
        await execAsync(`screencapture -x ${outputPath}`);
        return { content: [{ type: "text", text: `Screenshot saved to: ${outputPath}` }] };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error: any) {
    return {
      content: [{ type: "text", text: error.message }],
      isError: true,
    };
  }
});

let transport: SSEServerTransport | null = null;

app.get("/sse", async (req, res) => {
  transport = new SSEServerTransport("/messages", res);
  await server.connect(transport);
});

app.post("/messages", async (req, res) => {
  if (transport) {
    await transport.handlePostMessage(req, res);
  } else {
    res.status(400).send("SSE connection not established");
  }
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`mac-local-manager running on http://localhost:${PORT}`);
});
