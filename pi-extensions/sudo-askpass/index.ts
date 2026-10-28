/**
 * sudo-askpass — permission-gated sudo for the pi agent.
 *
 * Replaces pi-archimedes-sudo. Design goals:
 *
 * 1. The agent NEVER sees, receives, or stores the sudo password. It is
 *    entered by the user in a KDE Plasma dialog (kdialog) launched by sudo
 *    itself via SUDO_ASKPASS + `sudo -A` — the password travels directly
 *    from the dialog to sudo and never enters the pi/agent process, argv,
 *    env, context, or logs.
 * 2. Every privileged command is confirmed by the user FIRST, showing the
 *    exact command and the agent-supplied reason. Without explicit approval
 *    nothing runs and no password dialog appears.
 * 3. A tool_call guard blocks the built-in `bash` tool from running `sudo`
 *    or `sudo -S`/`sudo -A` directly, so the agent cannot sidestep this
 *    flow or reach a shell that gets the password.
 *
 * Password security is enforced by construction: we never read or write a
 * password; we only pass `-A` and let sudo call SUDO_ASKPASS (kdialog).
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import type { ExtensionAPI, ExtensionContext, ToolDefinition } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";

// ── Schema ───────────────────────────────────────────────────────────────

const SudoAskpassParamsSchema = Type.Object({
	command: Type.String({
		description:
			"Exact command and arguments to run with elevated privileges, e.g. \"apt install ripgrep\". Do NOT include a leading 'sudo'. Passed directly to sudo's argv — no shell: avoid pipes, redirects, &&, env assignments; pass args space-separated.",
	}),
	reason: Type.String({
		description:
			"Human-readable explanation of why this privileged command is needed. Shown to the user for approval, so it should be specific and honest.",
	}),
});

type SudoAskpassInput = Static<typeof SudoAskpassParamsSchema>;

// ── Askpass helper resolution ────────────────────────────────────────────

function resolveAskpass(): string | null {
	if (process.env.SUDO_ASKPASS) return process.env.SUDO_ASKPASS;
	const fallback = `${process.env.HOME ?? ""}/.config/askpass`;
	return fallback;
}

// ── Minimal POSIX-ish word splitter (no shell) ──────────────────────────
// Handles single quotes (literal), double quotes (\" and \\ escapes), and
// backslash escapes outside quotes. No pipes/redirects/&&/env are
// interpreted — they pass through literally, so sudo never runs a shell.
function splitCommandIntoArgv(command: string): string[] {
	const args: string[] = [];
	let current = "";
	let hasWord = false;
	let i = 0;
	const appendWord = () => {
		args.push(current);
		current = "";
		hasWord = false;
	};
	while (i < command.length) {
		const ch = command[i];
		if (ch === "'") {
			i++;
			while (i < command.length) {
				const inner = command[i];
				if (inner === "'") {
					i++;
					break;
				}
				current += inner;
				i++;
			}
			hasWord = true;
		} else if (ch === '"') {
			i++;
			while (i < command.length) {
				const inner = command[i];
				if (inner === "\\" && (command[i + 1] === '"' || command[i + 1] === "\\")) {
					current += command[i + 1];
					i += 2;
					continue;
				}
				if (inner === '"') {
					i++;
					break;
				}
				current += inner;
				i++;
			}
			hasWord = true;
		} else if (ch === "\\") {
			if (i + 1 < command.length) {
				current += command[i + 1];
				i += 2;
			} else {
				current += ch;
				i++;
			}
			hasWord = true;
		} else if (/\s/.test(ch)) {
			if (hasWord) appendWord();
			i++;
		} else {
			current += ch;
			hasWord = true;
			i++;
		}
	}
	if (hasWord) appendWord();
	return args;
}

// ── The tool ─────────────────────────────────────────────────────────────

function createSudoAskpassTool(): ToolDefinition<typeof SudoAskpassParamsSchema> {
	return {
		name: "sudo_askpass",
		label: "Sudo (askpass)",
		description:
			"Run a command with elevated (root) privileges after the user approves it. Shows the command and your reason for approval; the sudo password is entered by the user in a GUI dialog and is NEVER visible to the agent. Use ONLY when elevation is required.",
		promptSnippet: "Run a command as root with explicit user approval.",
		promptGuidelines: [
			"When a task requires elevated privileges, use sudo_askpass with a clear reason rather than trying to invoke sudo directly.",
			"The sudo_askpass tool shows the user the exact command and your stated reason and requires their approval before anything runs.",
			"The password is never passed through the agent; the user enters it in a GUI dialog.",
		],

		parameters: SudoAskpassParamsSchema,

		async execute(_toolCallId, params: SudoAskpassInput, signal, ..._rest): Promise<{ content: { type: "text"; text: string }[]; details: Record<string, unknown> }> {
			// ctx is the 5th arg; pull it from the tuple
			const ctx = _rest[_rest.length - 1] as ExtensionContext;
			const { command, reason } = params;
			const argv = splitCommandIntoArgv(command);
			if (argv.length === 0) {
				return { content: [{ type: "text", text: "Empty command." }], details: { command, approved: false } };
			}

			// 1. Require interactive UI for approval.
			if (!ctx.hasUI || ctx.mode !== "tui") {
				return {
					content: [
						{
							type: "text",
							text: "sudo_askpass requires an interactive session (TUI) for approval and the GUI password dialog. Refusing in headless/RPC mode.",
						},
					],
					details: { command, reason, approved: false },
				};
			}

			// 2. Ask for explicit approval showing command + reason, BEFORE any dialog.
			const message = [
				"This will run with elevated privileges:",
				"",
				`  $ ${command}`,
				"",
				`  Reason: ${reason}`,
				"",
				"The sudo password will be requested in a GUI dialog after you approve.",
			].join("\n");
			const approved = await ctx.ui.confirm("Confirm privileged command", message);
			if (!approved) {
				return {
					content: [{ type: "text", text: "Command not approved — nothing was run, no password dialog was shown." }],
					details: { command, reason, approved: false },
				};
			}

			// 3. Resolve askpass (kdialog) helper.
			const askpass = resolveAskpass();
			if (!askpass) {
				return { content: [{ type: "text", text: "No SUDO_ASKPASS helper configured; cannot prompt for a password." }], details: { command, approved: true } };
			}
			if (!existsSync(askpass)) {
				return { content: [{ type: "text", text: `Askpass helper not found at ${askpass}. Is kdialog installed?` }], details: { command, approved: true } };
			}

			// 4. Run `sudo -A <argv>`: sudo invokes askpass (kdialog) for the
			//    password itself. We never see or handle the password.
			const result = await runSudoArgs(argv, askpass, signal);
			return {
				content: [
					{
						type: "text",
						text:
							`exit code: ${result.exitCode ?? "null"}\n` +
							(result.stdout ? `stdout:\n${result.stdout}` : "") +
							(result.stderr ? `stderr:\n${result.stderr}` : "") +
							(result.error ? `error: ${result.error}` : ""),
					},
				],
				details: { command, reason, approved: true, exitCode: result.exitCode },
			};
		},
	};
}

interface SudoResult {
	exitCode: number | null;
	stdout: string;
	stderr: string;
	error?: string;
}

function runSudoArgs(argv: string[], askpass: string, signal?: AbortSignal): Promise<SudoResult> {
	return new Promise((resolve) => {
		let stdout = "";
		let stderr = "";
		const child = spawn("sudo", ["-A", "--", ...argv], {
			env: { ...process.env, SUDO_ASKPASS: askpass },
			stdio: ["ignore", "pipe", "pipe"],
		});
		child.stdout?.on("data", (d: Buffer) => (stdout += d.toString()));
		child.stderr?.on("data", (d: Buffer) => (stderr += d.toString()));
		child.on("error", (err: Error) => resolve({ exitCode: -1, stdout, stderr, error: err.message }));
		child.on("close", (code: number | null) => resolve({ exitCode: code, stdout, stderr }));
		if (signal) {
			if (signal.aborted) child.kill("SIGKILL");
			else signal.addEventListener("abort", () => child.kill("SIGKILL"), { once: true });
		}
	});
}

// ── Bash guard: block raw sudo in the built-in bash tool ────────────────

function looksLikeSudo(command: string): boolean {
	return /(^|[\s|;&])sudo(\s+(?:-[A-Za-z]+)?)?(\s|$)/i.test(command);
}

// ── Registration ──────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI): void {
	pi.registerTool(createSudoAskpassTool());

	// Block direct sudo in the bash tool so the agent can't reach stdin-typing
	// or otherwise handle the password. Everything elevated goes through the
	// sudo_askpass tool above.
	pi.on("tool_call", (event) => {
		if (event.toolName !== "bash") return undefined;
		const input = event.input as { command?: unknown } | undefined;
		const command = typeof input?.command === "string" ? input.command : "";
		if (looksLikeSudo(command)) {
			return {
				block: true,
				reason:
					"Direct `sudo` in the bash tool is blocked. Use the sudo_askpass tool instead, which prompts you for approval and requests the password via a GUI dialog.",
			};
		}
		return undefined;
	});
}
