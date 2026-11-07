import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { retainStableRequestId } from "./request-id";

describe("retainStableRequestId", () => {
  it("keeps the same id across retries of one payload", () => {
    let n = 0;
    const allocate = () => `id-${++n}`;
    const first = retainStableRequestId(null, "payload-a", allocate);
    const retry = retainStableRequestId(first, "payload-a", allocate);
    assert.equal(first.requestId, "id-1");
    assert.equal(retry.requestId, "id-1");
    assert.equal(n, 1);
  });

  it("allocates a new id when the payload changes", () => {
    let n = 0;
    const allocate = () => `id-${++n}`;
    const first = retainStableRequestId(null, "payload-a", allocate);
    const next = retainStableRequestId(first, "payload-b", allocate);
    assert.equal(next.requestId, "id-2");
  });
});
