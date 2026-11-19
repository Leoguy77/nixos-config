/**
 * keyfailover — move to the next API key when the provider rejects the current one.
 *
 * Pi retries on 429/5xx but treats 401/403 as terminal, so a rate-limited or
 * revoked key fails the whole request. `message_end` runs for every finalized
 * message and may replace it; rewriting the error to a retryable one makes Pi
 * retry, and the retry re-resolves the `!command` apiKey in models.json
 * (verified: commands re-run on every provider request, not once per process).
 *
 * So this extension only needs to advance a counter. kisski-key reads it.
 *
 * ponytail: counter is a plain file in the cache dir, so the index persists
 * across sessions (sticky to the last key tried). Good enough for 3 keys; a
 * journal would only matter if you wanted per-key cooldown/expiry.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const KEY_COUNT = 3;
const RETRY_STATUSES = ["401", "403", "429"];

const STATE = join(
  process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache"),
  "pi-kisski-key",
);

function readIndex(): number {
  try {
    const n = Number(readFileSync(STATE, "utf8").trim());
    return Number.isInteger(n) && n >= 0 && n < KEY_COUNT ? n : 0;
  } catch {
    return 0;
  }
}

function writeIndex(n: number): void {
  mkdirSync(dirname(STATE), { recursive: true });
  writeFileSync(STATE, String(n));
}

export default function (pi: ExtensionAPI): void {
  pi.on("message_end", (event) => {
    const message = event.message;
    if (message.role !== "assistant") return;
    if (message.stopReason !== "error") return; // this key works; stay on it

    const error = message.errorMessage ?? "";
    const status = /^(\d{3})\b/.exec(error)?.[1];
    if (!status || !RETRY_STATUSES.includes(status)) return;

    // Always advance, wrapping back to the first key. A rate-limited key has
    // usually cooled down by the time we come round again — Pi spaces attempts
    // by baseDelayMs * 2^attempt, capped at 60s — so wrapping recovers from a
    // transient 429 that a one-way walk leaves stuck on the last key forever.
    // The loop cannot run away: Pi's own retry budget (maxRetries) bounds how
    // many attempts happen in one run.
    writeIndex((readIndex() + 1) % KEY_COUNT);

    // 429 is already retryable; rewriting 401/403 into one is what makes Pi
    // retry those instead of failing the request outright. Don't prefix a 429
    // that already is one, or the message reads "429: 429: ...".
    const rewritten = status === "429" ? error : `429: ${error}`;
    return { message: { ...message, errorMessage: rewritten } };
  });
}
