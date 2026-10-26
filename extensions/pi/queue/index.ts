/**
 * /queue — FIFO task queue for pi.
 *
 * Queues prompts while the agent is busy and starts each one only after
 * Pi has fully settled (no automatic work, retries, or queued follow-ups
 * left), so tasks run strictly one after another.
 *
 *   /queue <task>   add a task (starts immediately if agent is idle)
 *   /queue list     show pending tasks
 *   /queue clear    drop pending tasks
 *
 * See README.md for details and limitations.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const queue: string[] = [];
	let dispatching = false;

	function pump(ctx: ExtensionContext) {
		if (dispatching || queue.length === 0) return;
		if (!ctx.isIdle()) return;
		dispatching = true;
		try {
			const task = queue.shift() as string;
			// Pi defers the prompt when sent from a settle handler (the promise
			// resolves right away); from the idle command path validation errors
			// reject asynchronously. The API types it `void`, hence Promise.resolve.
			// Re-queue on failure so no task is silently lost.
			Promise.resolve(pi.sendUserMessage(task)).catch((err: unknown) => {
				queue.unshift(task);
				ctx.ui.notify(
					`queued task did not start (${err instanceof Error ? err.message : String(err)}) — returned to queue`,
					"warning",
				);
			});
			ctx.ui.notify(`▶ queued task started (${queue.length} remaining)`, "info");
		} finally {
			dispatching = false;
		}
	}

	// Fired when Pi has no automatic continuation work left.
	// After an abort (Ctrl+C) Pi still settles — with aborted: true — but the
	// user meant to stop this work, so we stay parked until the next settle,
	// prompt, or /queue command.
	pi.on("agent_settled", (event, ctx) => {
		if (event.aborted) {
			if (queue.length > 0) {
				ctx.ui.notify(`run aborted — ${queue.length} queued task(s) waiting`, "info");
			}
			return;
		}
		pump(ctx);
	});

	pi.registerCommand("queue", {
		description: "Run tasks one after another: /queue <task> | /queue list | /queue clear",
		handler: async (args, ctx) => {
			const text = args.trim();
			if (!text) {
				ctx.ui.notify("Usage: /queue <task> | /queue list | /queue clear", "warning");
				return;
			}
			if (text === "list") {
				ctx.ui.notify(
					queue.length === 0
						? "queue is empty"
						: queue.map((q, i) => `${i + 1}. ${q}`).join("\n"),
					"info",
				);
				return;
			}
			if (text === "clear") {
				const n = queue.length;
				queue.length = 0;
				ctx.ui.notify(n > 0 ? `cleared ${n} queued task(s)` : "queue is empty", "info");
				return;
			}

			queue.push(text);
			if (ctx.isIdle()) {
				pump(ctx); // nothing running — start right away
			} else {
				ctx.ui.notify(
					`queued (position ${queue.length}) — starts after the current work settles`,
					"info",
				);
			}
		},
	});
}
