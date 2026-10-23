import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

function element() {
  return {
    hidden: false, disabled: false, value: '', textContent: '',
    setAttribute() {}, focus() {}, replaceChildren() {}, reset() {},
    querySelector() { return this.button ||= element(); },
  };
}

async function fixture(fetchImpl) {
  const elements = new Map();
  const get = (id) => {
    if (!elements.has(id)) elements.set(id, element());
    return elements.get(id);
  };
  const form = get('feedback-form');
  form.elements = {
    userId: { value: 'student' },
    problem: { value: '请保留已经填写的反馈内容' },
    consent: { checked: true }, contact: {}, contactType: {},
  };
  get('lookup-form').elements = { id: { value: 'TP-TEST' } };
  const timers = new Map();
  let nextTimer = 0, calls = 0;
  const context = vm.createContext({
    location: { hostname: 'localhost', origin: 'http://localhost' },
    document: { getElementById: get, querySelector: () => element() },
    FormData: class {
      constructor(form) { this.form = form; }
      *[Symbol.iterator]() {
        for (const [key, value] of Object.entries(this.form.elements)) {
          yield [key, value.value];
        }
      }
    },
    TypeError, AbortController,
    fetch: (...args) => { calls++; return fetchImpl(...args); },
    setTimeout(fn) { const id = ++nextTimer; timers.set(id, fn); return id; },
    clearTimeout(id) { timers.delete(id); },
  });
  const common = await readFile(new URL('../public/common.js', import.meta.url), 'utf8');
  const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
  vm.runInContext(common.replace(/^export /gm, ''), context);
  vm.runInContext(app.replace(/^import .*$/m, ''), context);
  return {
    get, form, calls: () => calls,
    expire() { for (const fn of [...timers.values()]) fn(); },
    pendingTimers: () => timers.size,
  };
}

test('successful submission reveals its receipt and releases the button', async () => {
  const f = await fixture(async () => ({ ok: true, json: async () => ({ id: 'TP-9' }) }));
  await f.form.onsubmit({ preventDefault() {} });
  assert.equal(f.get('receipt-id').textContent, 'TP-9');
  assert.equal(f.get('receipt').hidden, false);
  assert.equal(f.form.hidden, true);
  assert.equal(f.form.querySelector().disabled, false);
  assert.equal(f.pendingTimers(), 0);
});

test('network failure keeps inputs and releases the submit button', async () => {
  const f = await fixture(async () => { throw new TypeError('Failed to fetch'); });
  await f.form.onsubmit({ preventDefault() {} });
  assert.match(f.get('form-message').textContent, /网络连接失败/);
  assert.equal(f.form.elements.problem.value, '请保留已经填写的反馈内容');
  assert.equal(f.form.hidden, false);
  assert.equal(f.form.querySelector().disabled, false);
  assert.equal(f.calls(), 1);
});

for (const mode of ['create', 'lookup']) {
  test(`${mode} timeout releases button without automatic retries`, async () => {
    let signal;
    const f = await fixture((_url, options) => {
      signal = options.signal;
      return new Promise(() => {});
    });
    const form = mode === 'create' ? f.form : f.get('lookup-form');
    const task = form.onsubmit({ preventDefault() {}, currentTarget: form });
    await Promise.resolve(); await Promise.resolve();
    assert.equal(form.querySelector().disabled, true);
    f.expire();
    await task;
    assert.equal(signal.aborted, true);
    assert.equal(form.querySelector().disabled, false);
    assert.equal(f.calls(), 1);
    assert.equal(f.pendingTimers(), 0);
    assert.match(f.get(mode === 'create' ? 'form-message' : 'lookup-message').textContent, /请求超时/);
    assert.equal(f.form.elements.problem.value, '请保留已经填写的反馈内容');
  });
}
