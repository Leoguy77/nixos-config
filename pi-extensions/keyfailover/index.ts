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
 * ponytail: counter is a plain file in the cache dir and `tried` lives in
 * memory, so the count resets at the start of each run and the index persists
 * across sessions (sticky to the last key that worked). Good enough for 3
 * keys; a journal would only matter if you wanted per-key cooldown/expiry.
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
  let tried = 0;

  pi.on("message_end", (event) => {
    const message = event.message;
    if (message.role !== "assistant") return;

    if (message.stopReason !== "error") {
      // A good response means the current key works; keep using it.
      tried = 0;
      return;
    }

    const error = message.errorMessage ?? "";
    const status = /^(\d{3})\b/.exec(error)?.[1];
    if (!status || !RETRY_STATUSES.includes(status)) return;

    // Every key has now failed: leave the error alone so Pi stops instead of
    // looping back to a key this run already rejected.
    if (tried >= KEY_COUNT - 1) return;

    tried += 1;
    writeIndex((readIndex() + 1) % KEY_COUNT);

    return { message: { ...message, errorMessage: `429: ${error}` } };
  });
}
