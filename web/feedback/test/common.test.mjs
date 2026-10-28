import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test.beforeEach((t) => {
  const original = globalThis.location;
  globalThis.location = { hostname: 'localhost' };
  t.after(() => {
    if (original === undefined) delete globalThis.location;
    else globalThis.location = original;
  });
});

async function loadCommon() {
  const source = await readFile(
    new URL("../public/common.js", import.meta.url),
    "utf8",
  );
  const dataUrl =
    "data:text/javascript;base64," + Buffer.from(source).toString("base64");
  return import(dataUrl);
}

function mockFetch(t, impl) {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = (url, options) => {
    calls.push({ url, options });
    return impl(url, options);
  };
  t.after(() => {
    globalThis.fetch = original;
  });
  return calls;
}

function mockTimers(t) {
  const originalSet = globalThis.setTimeout;
  const originalClear = globalThis.clearTimeout;
  const pending = new Map();
  let nextId = 1;
  globalThis.setTimeout = (fn, ms) => {
    const id = nextId++;
    pending.set(id, { fn, ms });
    return id;
  };
  globalThis.clearTimeout = (id) => {
    pending.delete(id);
  };
  t.after(() => {
    globalThis.setTimeout = originalSet;
    globalThis.clearTimeout = originalClear;
  });
  return {
    fire() {
      const entries = [...pending.values()];
      pending.clear();
      for (const { fn } of entries) fn();
    },
    get size() {
      return pending.size;
    },
  };
}

test("success resolves parsed result and clears timer", async (t) => {
  const timers = mockTimers(t);
  const calls = mockFetch(t, () =>
    Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve({ id: "TP-1" }),
    }),
  );
  const { api } = await loadCommon();
  const result = await api("lookup", { id: "TP-1" });
  assert.deepEqual(result, { id: "TP-1" });
  assert.equal(calls.length, 1);
  assert.equal(timers.size, 0);
});

test("http error surfaces server message and status", async (t) => {
  mockTimers(t);
  mockFetch(t, () =>
    Promise.resolve({
      ok: false,
      status: 400,
      json: () => Promise.resolve({ error: "无效工单" }),
    }),
  );
  const { api } = await loadCommon();
  await assert.rejects(api("lookup", {}), (error) => {
    assert.equal(error.message, "无效工单");
    assert.equal(error.status, 400);
    return true;
  });
});

test("invalid body json yields friendly message", async (t) => {
  mockTimers(t);
  mockFetch(t, () =>
    Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.reject(new SyntaxError("bad json")),
    }),
  );
  const { api } = await loadCommon();
  await assert.rejects(api("lookup", {}), { message: "服务暂时不可用，请稍后重试" });
});

test("network TypeError maps to translated message", async (t) => {
  mockTimers(t);
  mockFetch(t, () => Promise.reject(new TypeError("Failed to fetch")));
  const { api } = await loadCommon();
  await assert.rejects(api("create", {}), {
    message: "网络连接失败，请检查网络后重试",
  });
});

test("hanging fetch aborts on timeout with create wording", async (t) => {
  const timers = mockTimers(t);
  let aborted = false;
  mockFetch(t, (_url, options) => {
    options.signal.addEventListener("abort", () => {
      aborted = true;
    });
    return new Promise(() => {});
  });
  const { api } = await loadCommon();
  const pending = api("create", {});
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(timers.size, 1);
  timers.fire();
  await assert.rejects(pending, {
    message: "请求超时，提交结果尚未确认，请勿连续重复提交",
  });
  assert.equal(aborted, true);
});

test("hanging body parse timeouts and clears timer", async (t) => {
  const timers = mockTimers(t);
  mockFetch(t, () =>
    Promise.resolve({ ok: true, status: 200, json: () => new Promise(() => {}) }),
  );
  const { api } = await loadCommon();
  const pending = api("lookup", {});
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(timers.size, 1);
  timers.fire();
  await assert.rejects(pending, { message: "请求超时，请稍后重试" });
  assert.equal(timers.size, 0);
});
