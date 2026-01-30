import { spawn, ChildProcess } from "child_process";
import { existsSync, mkdirSync, writeFileSync, readFileSync, unlinkSync } from "fs";
import { join } from "path";
import { tmpdir, homedir, hostname } from "os";
import { createServer } from "net";

// Types for opencode JSON output events
interface OpencodeEvent {
  type: string;
  timestamp: number;
  sessionID: string;
  part?: {
    id: string;
    sessionID: string;
    messageID: string;
    type: string;
    text?: string;
    tool?: string;
    input?: any;
    output?: string;
    metadata?: any;
    reason?: string;
    cost?: number;
    tokens?: {
      input: number;
      output: number;
      reasoning?: number;
      cache?: { read: number; write: number };
    };
  };
}

interface OpencodeResult {
  success: boolean;
  sessionId: string;
  textOutput: string;
  toolCalls: Array<{
    tool: string;
    input: any;
    output: string;
  }>;
  cost?: number;
  tokens?: {
    input: number;
    output: number;
    reasoning?: number;
  };
  error?: string;
}

// Parse NDJSON output from opencode
function parseOpencodeOutput(output: string): OpencodeResult {
  const lines = output.trim().split("\n").filter(Boolean);
  const events: OpencodeEvent[] = [];

  for (const line of lines) {
    try {
      events.push(JSON.parse(line));
    } catch (e) {
      // Skip non-JSON lines (might be stderr mixed in)
    }
  }

  let sessionId = "";
  let textOutput = "";
  const toolCalls: Array<{ tool: string; input: any; output: string }> = [];
  let cost: number | undefined;
  let tokens: { input: number; output: number; reasoning?: number } | undefined;
  let lastToolCall: { tool: string; input: any; output: string } | null = null;

  for (const event of events) {
    if (event.sessionID) {
      sessionId = event.sessionID;
    }

    if (event.type === "text" && event.part?.text) {
      textOutput += event.part.text;
    }

    if (event.type === "tool_start" && event.part?.tool) {
      lastToolCall = {
        tool: event.part.tool,
        input: event.part.input || {},
        output: "",
      };
    }

    if (event.type === "tool_finish" && lastToolCall) {
      lastToolCall.output = event.part?.output || "";
      toolCalls.push(lastToolCall);
      lastToolCall = null;
    }

    if (event.type === "step_finish" && event.part) {
      if (event.part.cost !== undefined) {
        cost = (cost || 0) + event.part.cost;
      }
      if (event.part.tokens) {
        if (!tokens) {
          tokens = { input: 0, output: 0, reasoning: 0 };
        }
        tokens.input += event.part.tokens.input || 0;
        tokens.output += event.part.tokens.output || 0;
        tokens.reasoning = (tokens.reasoning || 0) + (event.part.tokens.reasoning || 0);
      }
    }
  }

  return {
    success: true,
    sessionId,
    textOutput,
    toolCalls,
    cost,
    tokens,
  };
}

// Run opencode with given parameters
async function runOpencode(options: {
  message: string;
  workdir: string;
  sessionId?: string;
  model?: string;
  agent?: string;
  files?: string[];
  timeout?: number;
}): Promise<OpencodeResult> {
  const { message, workdir, sessionId, model, agent, files, timeout = 300000 } = options;

  // Build command arguments
  const args = ["run", "--format", "json"];

  if (sessionId) {
    args.push("--session", sessionId);
  }

  if (model) {
    args.push("--model", model);
  }

  if (agent) {
    args.push("--agent", agent);
  }

  if (files && files.length > 0) {
    for (const file of files) {
      args.push("--file", file);
    }
  }

  args.push(message);

  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";

    const opencodeBin = findOpencodeBinary();

    const proc = spawn(opencodeBin, args, {
      cwd: workdir,
      env: {
        ...process.env,
        // Ensure no TTY-related issues
        TERM: "dumb",
        NO_COLOR: "1",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Close stdin immediately - we don't need interactive input
    proc.stdin.end();

    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    const timeoutId = setTimeout(() => {
      proc.kill("SIGTERM");
      resolve({
        success: false,
        sessionId: "",
        textOutput: "",
        toolCalls: [],
        error: `Timeout after ${timeout / 1000} seconds. Partial output: ${stdout.slice(0, 500)}`,
      });
    }, timeout);

    proc.on("close", (code) => {
      clearTimeout(timeoutId);

      if (code !== 0 && !stdout) {
        resolve({
          success: false,
          sessionId: "",
          textOutput: "",
          toolCalls: [],
          error: `opencode exited with code ${code}. stderr: ${stderr}`,
        });
        return;
      }

      try {
        const result = parseOpencodeOutput(stdout);
        if (stderr && !result.textOutput) {
          result.error = stderr;
        }
        resolve(result);
      } catch (e: any) {
        resolve({
          success: false,
          sessionId: "",
          textOutput: "",
          toolCalls: [],
          error: `Failed to parse opencode output: ${e.message}. Raw: ${stdout.slice(0, 500)}`,
        });
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timeoutId);
      resolve({
        success: false,
        sessionId: "",
        textOutput: "",
        toolCalls: [],
        error: `Failed to spawn opencode: ${err.message}`,
      });
    });
  });
}

// Server instance tracking
interface ServerInstance {
  name: string;
  process: ChildProcess;
  port: number;
  workdir: string;
  startedAt: Date;
  hostname: string;
  url: string;
  tailscaleUrl?: string;
}

// Find an available port
async function findAvailablePort(startPort: number = 4096): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(startPort, "0.0.0.0", () => {
      const addr = server.address();
      const port = typeof addr === "object" && addr ? addr.port : startPort;
      server.close(() => resolve(port));
    });
    server.on("error", () => {
      // Port in use, try next
      if (startPort < 65535) {
        resolve(findAvailablePort(startPort + 1));
      } else {
        reject(new Error("No available ports"));
      }
    });
  });
}

// Get Tailscale hostname if available
async function getTailscaleHostname(): Promise<string | null> {
  return new Promise((resolve) => {
    const proc = spawn("tailscale", ["status", "--json"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.on("close", (code) => {
      if (code !== 0) {
        resolve(null);
        return;
      }
      try {
        const status = JSON.parse(stdout);
        if (status.Self?.DNSName) {
          // Remove trailing dot
          resolve(status.Self.DNSName.replace(/\.$/, ""));
        } else {
          resolve(null);
        }
      } catch {
        resolve(null);
      }
    });

    proc.on("error", () => resolve(null));

    // Timeout after 5 seconds
    setTimeout(() => {
      proc.kill();
      resolve(null);
    }, 5000);
  });
}

// Find opencode binary
function findOpencodeBinary(): string {
  const username = process.env.USER || "chris";
  const opencodePaths = [
    `/etc/profiles/per-user/${username}/bin/opencode`, // NixOS per-user profile
    join(homedir(), ".nix-profile/bin/opencode"),
    "/run/current-system/sw/bin/opencode",
    "/usr/local/bin/opencode",
    "opencode", // fallback to PATH
  ];

  for (const p of opencodePaths) {
    if (p === "opencode" || existsSync(p)) {
      return p;
    }
  }
  return "opencode";
}

export default function (api: any) {
  // Store active sessions for multi-turn conversations
  const activeSessions: Map<string, { sessionId: string; workdir: string }> = new Map();

  // Store running server instances
  const runningServers: Map<string, ServerInstance> = new Map();

  // Main coding task delegation tool
  api.registerTool({
    name: "opencode_delegate",
    description: `Delegate a complex coding task to opencode, a powerful AI coding assistant with access to file editing, terminal commands, web search, and specialized sub-agents. Use this for:
- Multi-file code changes
- Complex refactoring
- Debugging and fixing issues
- Creating new features
- Code review and improvements
- Any task requiring multiple steps or tool use

opencode runs non-interactively and returns results. For multi-step tasks, use the session_key to continue conversations.`,
    parameters: {
      type: "object",
      properties: {
        task: {
          type: "string",
          description:
            "Detailed description of the coding task. Be specific about what you want done, which files to modify, and expected outcomes.",
        },
        workdir: {
          type: "string",
          description:
            "Working directory for the task. This should be the project root. Defaults to ~/dotfiles if not specified.",
        },
        session_key: {
          type: "string",
          description:
            "Optional key to identify a multi-turn session. Use the same key to continue a previous conversation. If not provided, starts a fresh session.",
        },
        model: {
          type: "string",
          description:
            "Model to use (e.g., 'anthropic/claude-sonnet-4-20250514', 'openai/gpt-4o'). Uses opencode's default if not specified.",
        },
        agent: {
          type: "string",
          description:
            "Specific agent to use (e.g., 'coder', 'explorer'). Uses opencode's default if not specified.",
        },
        files: {
          type: "array",
          items: { type: "string" },
          description: "Optional list of file paths to attach as context for the task.",
        },
        timeout_seconds: {
          type: "number",
          description: "Timeout in seconds. Default is 300 (5 minutes). Max is 600 (10 minutes).",
        },
      },
      required: ["task"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const task = args.task;
      const workdir = args.workdir || join(homedir(), "dotfiles");
      const sessionKey = args.session_key;
      const model = args.model;
      const agent = args.agent;
      const files = args.files;
      const timeoutSeconds = Math.min(args.timeout_seconds || 300, 600);

      // Validate workdir exists
      if (!existsSync(workdir)) {
        return {
          content: [
            {
              type: "text",
              text: `Error: Working directory does not exist: ${workdir}`,
            },
          ],
        };
      }

      // Check for existing session
      let sessionId: string | undefined;
      if (sessionKey && activeSessions.has(sessionKey)) {
        const session = activeSessions.get(sessionKey)!;
        sessionId = session.sessionId;
        // Warn if workdir changed
        if (session.workdir !== workdir) {
          // Clear session if workdir changed
          activeSessions.delete(sessionKey);
          sessionId = undefined;
        }
      }

      try {
        const result = await runOpencode({
          message: task,
          workdir,
          sessionId,
          model,
          agent,
          files,
          timeout: timeoutSeconds * 1000,
        });

        // Store session for continuation
        if (sessionKey && result.sessionId) {
          activeSessions.set(sessionKey, {
            sessionId: result.sessionId,
            workdir,
          });
        }

        if (!result.success) {
          return {
            content: [
              {
                type: "text",
                text: `opencode task failed: ${result.error}`,
              },
            ],
            details: { success: false, error: result.error },
          };
        }

        // Format the response
        let response = `## opencode Task Complete\n\n`;

        if (result.textOutput) {
          response += `### Response\n${result.textOutput}\n\n`;
        }

        if (result.toolCalls.length > 0) {
          response += `### Actions Taken (${result.toolCalls.length} tool calls)\n`;
          for (const tc of result.toolCalls) {
            response += `- **${tc.tool}**`;
            if (tc.tool === "edit" && tc.input?.filePath) {
              response += `: ${tc.input.filePath}`;
            } else if (tc.tool === "write" && tc.input?.filePath) {
              response += `: ${tc.input.filePath}`;
            } else if (tc.tool === "bash" && tc.input?.command) {
              const cmd = tc.input.command.slice(0, 50);
              response += `: \`${cmd}${tc.input.command.length > 50 ? "..." : ""}\``;
            } else if (tc.tool === "read" && tc.input?.filePath) {
              response += `: ${tc.input.filePath}`;
            }
            response += "\n";
          }
          response += "\n";
        }

        if (result.cost !== undefined) {
          response += `**Cost:** $${result.cost.toFixed(4)}`;
          if (result.tokens) {
            response += ` (${result.tokens.input} in, ${result.tokens.output} out)`;
          }
          response += "\n";
        }

        if (sessionKey) {
          response += `\n*Session key: ${sessionKey} - use same key to continue this conversation*`;
        }

        return {
          content: [{ type: "text", text: response }],
          details: {
            success: true,
            sessionId: result.sessionId,
            sessionKey,
            textOutput: result.textOutput,
            toolCallCount: result.toolCalls.length,
            toolCalls: result.toolCalls,
            cost: result.cost,
            tokens: result.tokens,
          },
        };
      } catch (error: any) {
        return {
          content: [
            {
              type: "text",
              text: `opencode delegation failed: ${error.message}`,
            },
          ],
          details: { success: false, error: error.message },
        };
      }
    },
  });

  // Quick code review tool
  api.registerTool({
    name: "opencode_review",
    description:
      "Quick code review using opencode. Analyzes code for quality, bugs, security issues, and improvements.",
    parameters: {
      type: "object",
      properties: {
        files: {
          type: "array",
          items: { type: "string" },
          description: "File paths to review",
        },
        focus: {
          type: "string",
          description:
            "What to focus on: 'security', 'performance', 'bugs', 'style', 'all' (default: 'all')",
          default: "all",
        },
        workdir: {
          type: "string",
          description: "Working directory (project root)",
        },
      },
      required: ["files"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const files = args.files;
      const focus = args.focus || "all";
      const workdir = args.workdir || join(homedir(), "dotfiles");

      const focusPrompts: Record<string, string> = {
        security: "Focus on security vulnerabilities, injection risks, and unsafe patterns.",
        performance: "Focus on performance issues, inefficiencies, and optimization opportunities.",
        bugs: "Focus on potential bugs, edge cases, and logic errors.",
        style: "Focus on code style, readability, and best practices.",
        all: "Review for bugs, security issues, performance, and code quality.",
      };

      const task = `Review the following files and provide feedback. ${focusPrompts[focus] || focusPrompts.all}

Files to review:
${files.map((f: string) => `- ${f}`).join("\n")}

Provide a structured review with:
1. Summary of findings
2. Critical issues (if any)
3. Suggestions for improvement
4. Overall assessment`;

      const result = await runOpencode({
        message: task,
        workdir,
        files,
        timeout: 180000, // 3 minutes for review
      });

      if (!result.success) {
        return {
          content: [{ type: "text", text: `Code review failed: ${result.error}` }],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `## Code Review Results\n\n${result.textOutput}`,
          },
        ],
        details: {
          success: true,
          files,
          focus,
          cost: result.cost,
        },
      };
    },
  });

  // Clear session tool
  api.registerTool({
    name: "opencode_clear_session",
    description: "Clear an opencode session to start fresh",
    parameters: {
      type: "object",
      properties: {
        session_key: {
          type: "string",
          description: "Session key to clear",
        },
      },
      required: ["session_key"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const sessionKey = args.session_key;

      if (activeSessions.has(sessionKey)) {
        activeSessions.delete(sessionKey);
        return {
          content: [{ type: "text", text: `Session '${sessionKey}' cleared.` }],
          details: { success: true, sessionKey },
        };
      }

      return {
        content: [{ type: "text", text: `No active session found with key '${sessionKey}'.` }],
        details: { success: false, sessionKey },
      };
    },
  });

  // List active sessions
  api.registerTool({
    name: "opencode_list_sessions",
    description: "List active opencode sessions",
    parameters: {
      type: "object",
      properties: {},
      required: [],
    },
    execute: async (_toolCallId: string, _args: any) => {
      if (activeSessions.size === 0) {
        return {
          content: [{ type: "text", text: "No active opencode sessions." }],
          details: { sessions: [] },
        };
      }

      const sessions = Array.from(activeSessions.entries()).map(([key, val]) => ({
        key,
        sessionId: val.sessionId,
        workdir: val.workdir,
      }));

      const text = sessions
        .map((s) => `- **${s.key}**: ${s.sessionId} (${s.workdir})`)
        .join("\n");

      return {
        content: [{ type: "text", text: `## Active Sessions\n\n${text}` }],
        details: { sessions },
      };
    },
  });

  // ============================================
  // Server Management Tools
  // ============================================

  // Start an opencode server
  api.registerTool({
    name: "opencode_server_start",
    description: `Start a headless opencode server that you can attach to from your laptop or other machines.
The server runs in the background and provides a URL you can use with 'opencode attach <url>'.
Useful for:
- Starting a coding session on the server that you can attach to from anywhere
- Long-running tasks that you want to monitor/interact with
- Collaborative debugging sessions`,
    parameters: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description:
            "A friendly name for this server instance (e.g., 'dotfiles-refactor', 'debug-session')",
        },
        workdir: {
          type: "string",
          description: "Working directory for the server. Defaults to ~/dotfiles",
        },
        port: {
          type: "number",
          description:
            "Port to listen on. If not specified, finds an available port starting from 4096",
        },
      },
      required: ["name"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const name = args.name;
      const workdir = args.workdir || join(homedir(), "dotfiles");
      const requestedPort = args.port;

      // Check if server with this name already exists
      if (runningServers.has(name)) {
        const existing = runningServers.get(name)!;
        return {
          content: [
            {
              type: "text",
              text: `Server '${name}' is already running at ${existing.url}\n\nTo attach: \`opencode attach ${existing.url}\`${existing.tailscaleUrl ? `\nOr via Tailscale: \`opencode attach ${existing.tailscaleUrl}\`` : ""}`,
            },
          ],
          details: {
            success: false,
            error: "Server already exists",
            existing: {
              name: existing.name,
              url: existing.url,
              tailscaleUrl: existing.tailscaleUrl,
            },
          },
        };
      }

      // Validate workdir
      if (!existsSync(workdir)) {
        return {
          content: [{ type: "text", text: `Error: Working directory does not exist: ${workdir}` }],
          details: { success: false, error: "Workdir not found" },
        };
      }

      try {
        // Find available port
        const port = requestedPort || (await findAvailablePort());

        // Get Tailscale hostname for remote access
        const tailscaleHost = await getTailscaleHostname();

        const opencodeBin = findOpencodeBinary();

        // Start the server
        const serverArgs = ["serve", "--port", String(port), "--hostname", "0.0.0.0"];

        const proc = spawn(opencodeBin, serverArgs, {
          cwd: workdir,
          env: {
            ...process.env,
            TERM: "dumb",
            NO_COLOR: "1",
          },
          stdio: ["pipe", "pipe", "pipe"],
          detached: true, // Run independently of parent
        });

        // Don't let the server process keep moltbot from exiting
        proc.unref();

        // Close stdin
        proc.stdin.end();

        // Wait a moment for the server to start
        await new Promise((resolve) => setTimeout(resolve, 2000));

        // Check if process is still running
        if (proc.exitCode !== null) {
          return {
            content: [
              {
                type: "text",
                text: `Failed to start server. Exit code: ${proc.exitCode}`,
              },
            ],
            details: { success: false, error: "Server exited immediately" },
          };
        }

        const localHostname = hostname();
        const localUrl = `http://localhost:${port}`;
        const tailscaleUrl = tailscaleHost ? `http://${tailscaleHost}:${port}` : undefined;

        const serverInstance: ServerInstance = {
          name,
          process: proc,
          port,
          workdir,
          startedAt: new Date(),
          hostname: localHostname,
          url: localUrl,
          tailscaleUrl,
        };

        runningServers.set(name, serverInstance);

        // Build response
        let response = `## opencode Server Started: ${name}\n\n`;
        response += `**Working Directory:** ${workdir}\n`;
        response += `**Port:** ${port}\n`;
        response += `**Started:** ${serverInstance.startedAt.toISOString()}\n\n`;
        response += `### How to Connect\n\n`;
        response += `**Local (on this machine):**\n\`\`\`\nopencode attach ${localUrl}\n\`\`\`\n\n`;

        if (tailscaleUrl) {
          response += `**Via Tailscale (from any device on your tailnet):**\n\`\`\`\nopencode attach ${tailscaleUrl}\n\`\`\`\n\n`;
        }

        response += `**Via SSH tunnel (if not on Tailscale):**\n\`\`\`\nssh -L ${port}:localhost:${port} chris@trainwreck\nopencode attach ${localUrl}\n\`\`\`\n`;

        return {
          content: [{ type: "text", text: response }],
          details: {
            success: true,
            name,
            port,
            workdir,
            localUrl,
            tailscaleUrl,
            hostname: localHostname,
          },
        };
      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Failed to start server: ${error.message}` }],
          details: { success: false, error: error.message },
        };
      }
    },
  });

  // Stop an opencode server
  api.registerTool({
    name: "opencode_server_stop",
    description: "Stop a running opencode server",
    parameters: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "Name of the server to stop",
        },
      },
      required: ["name"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const name = args.name;

      if (!runningServers.has(name)) {
        return {
          content: [{ type: "text", text: `No server found with name '${name}'` }],
          details: { success: false, error: "Server not found" },
        };
      }

      const server = runningServers.get(name)!;

      try {
        // Kill the process
        server.process.kill("SIGTERM");

        // Wait a moment for graceful shutdown
        await new Promise((resolve) => setTimeout(resolve, 1000));

        // Force kill if still running
        if (server.process.exitCode === null) {
          server.process.kill("SIGKILL");
        }

        runningServers.delete(name);

        return {
          content: [
            {
              type: "text",
              text: `Server '${name}' stopped.\n\n**Was running on:** ${server.url}\n**Uptime:** ${Math.round((Date.now() - server.startedAt.getTime()) / 1000 / 60)} minutes`,
            },
          ],
          details: { success: true, name },
        };
      } catch (error: any) {
        return {
          content: [{ type: "text", text: `Failed to stop server: ${error.message}` }],
          details: { success: false, error: error.message },
        };
      }
    },
  });

  // List running servers
  api.registerTool({
    name: "opencode_server_list",
    description: "List all running opencode servers",
    parameters: {
      type: "object",
      properties: {},
      required: [],
    },
    execute: async (_toolCallId: string, _args: any) => {
      if (runningServers.size === 0) {
        return {
          content: [
            {
              type: "text",
              text: "No opencode servers currently running.\n\nUse `opencode_server_start` to start one.",
            },
          ],
          details: { servers: [] },
        };
      }

      // Check which servers are still alive
      const aliveServers: ServerInstance[] = [];
      const deadServers: string[] = [];

      for (const [name, server] of runningServers) {
        if (server.process.exitCode !== null) {
          deadServers.push(name);
        } else {
          aliveServers.push(server);
        }
      }

      // Clean up dead servers
      for (const name of deadServers) {
        runningServers.delete(name);
      }

      if (aliveServers.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "No opencode servers currently running.\n\nUse `opencode_server_start` to start one.",
            },
          ],
          details: { servers: [] },
        };
      }

      let response = `## Running opencode Servers\n\n`;

      for (const server of aliveServers) {
        const uptime = Math.round((Date.now() - server.startedAt.getTime()) / 1000 / 60);
        response += `### ${server.name}\n`;
        response += `- **URL:** ${server.url}\n`;
        if (server.tailscaleUrl) {
          response += `- **Tailscale:** ${server.tailscaleUrl}\n`;
        }
        response += `- **Workdir:** ${server.workdir}\n`;
        response += `- **Uptime:** ${uptime} minutes\n`;
        response += `- **Attach:** \`opencode attach ${server.tailscaleUrl || server.url}\`\n\n`;
      }

      return {
        content: [{ type: "text", text: response }],
        details: {
          servers: aliveServers.map((s) => ({
            name: s.name,
            url: s.url,
            tailscaleUrl: s.tailscaleUrl,
            workdir: s.workdir,
            uptime: Math.round((Date.now() - s.startedAt.getTime()) / 1000 / 60),
          })),
        },
      };
    },
  });

  // Get server info/connection details
  api.registerTool({
    name: "opencode_server_info",
    description: "Get connection details for a running opencode server",
    parameters: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "Name of the server",
        },
      },
      required: ["name"],
    },
    execute: async (_toolCallId: string, args: any) => {
      const name = args.name;

      if (!runningServers.has(name)) {
        return {
          content: [{ type: "text", text: `No server found with name '${name}'` }],
          details: { success: false, error: "Server not found" },
        };
      }

      const server = runningServers.get(name)!;

      // Check if still alive
      if (server.process.exitCode !== null) {
        runningServers.delete(name);
        return {
          content: [
            {
              type: "text",
              text: `Server '${name}' has stopped (exit code: ${server.process.exitCode})`,
            },
          ],
          details: { success: false, error: "Server stopped" },
        };
      }

      const uptime = Math.round((Date.now() - server.startedAt.getTime()) / 1000 / 60);

      let response = `## Server: ${name}\n\n`;
      response += `**Status:** Running\n`;
      response += `**Port:** ${server.port}\n`;
      response += `**Working Directory:** ${server.workdir}\n`;
      response += `**Started:** ${server.startedAt.toISOString()}\n`;
      response += `**Uptime:** ${uptime} minutes\n\n`;
      response += `### Connection URLs\n\n`;
      response += `**Local:** ${server.url}\n`;
      if (server.tailscaleUrl) {
        response += `**Tailscale:** ${server.tailscaleUrl}\n`;
      }
      response += `\n### Quick Connect\n\n`;
      response += `\`\`\`bash\nopencode attach ${server.tailscaleUrl || server.url}\n\`\`\`\n`;

      return {
        content: [{ type: "text", text: response }],
        details: {
          success: true,
          name: server.name,
          port: server.port,
          workdir: server.workdir,
          url: server.url,
          tailscaleUrl: server.tailscaleUrl,
          uptime,
        },
      };
    },
  });
}
