import test from 'node:test';
import assert from 'node:assert/strict';

import { apply, createDemoState, createHandler, name, PREFIX } from '../lib/index.js';

/** 假的 HTTP response：把 writeHead/end 的结果记下来供断言。 */
function createFakeResponse() {
  const record = { status: 0, headers: {}, body: '' };
  return {
    record,
    writeHead(status, headers) {
      record.status = status;
      Object.assign(record.headers, headers ?? {});
    },
    end(body) {
      record.body = body ?? '';
    },
    /** 把 body 当 JSON 解析。 */
    json() {
      return JSON.parse(record.body);
    },
  };
}

/** 假的 HTTP request：handler 只用 method/url/headers 三个字段。 */
function createFakeRequest(method, url, headers = {}) {
  return { method, url, headers, on() {} };
}

/**
 * 用假 ctx 把宿主半侧挂起来，返回注册得到的路由。
 * 断言了 inject 依赖列表，插件改坏依赖会立刻失败。
 */
function mountHost() {
  const routes = [];
  const disposers = [];
  const hostCtx = {
    effect(fn) {
      const dispose = fn();
      if (typeof dispose === 'function') disposers.push(dispose);
      return dispose;
    },
    webServer: {
      register(spec) {
        routes.push(spec);
        return () => {
          const index = routes.indexOf(spec);
          if (index >= 0) routes.splice(index, 1);
        };
      },
    },
  };
  const ctx = {
    logger: { info() {}, warn() {}, debug() {} },
    inject(deps, install) {
      assert.deepEqual(deps, ['webServer'], '宿主插件只应声明 webServer 依赖');
      install(hostCtx);
    },
  };
  apply(ctx);
  return { routes, disposers };
}

test('插件名与 package.json 一致', () => {
  assert.equal(name, 'dsh-demo-plugin');
});

test('注册了唯一一条 /dsh-demo-plugin 前缀路由', () => {
  const { routes } = mountHost();
  assert.equal(routes.length, 1);
  assert.equal(routes[0].kind, 'prefix');
  assert.equal(routes[0].path, PREFIX);
  assert.equal(typeof routes[0].handler, 'function');
});

test('GET /hello 返回消息与累加的点击次数', async () => {
  const { routes } = mountHost();
  const handler = routes[0].handler;

  const first = createFakeResponse();
  await handler(createFakeRequest('GET', PREFIX + '/hello'), first);
  assert.equal(first.record.status, 200);
  assert.match(first.record.headers['content-type'], /application\/json/);
  const payload = first.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.message, '插件跑起来啦 👋');
  assert.equal(payload.hits, 1);
  assert.equal(payload.node, process.version);

  const second = createFakeResponse();
  await handler(createFakeRequest('GET', PREFIX + '/hello'), second);
  assert.equal(second.json().hits, 2, '点击次数应当累加');
});

test('前缀根路径 / 与 /hello 等价', async () => {
  const { routes } = mountHost();
  const response = createFakeResponse();
  await routes[0].handler(createFakeRequest('GET', PREFIX + '/'), response);
  assert.equal(response.record.status, 200);
  assert.equal(response.json().ok, true);
});

test('非 GET 方法返回 405', async () => {
  const { routes } = mountHost();
  const response = createFakeResponse();
  await routes[0].handler(createFakeRequest('POST', PREFIX + '/hello'), response);
  assert.equal(response.record.status, 405);
  assert.equal(response.json().ok, false);
});

test('未知子路径返回 404 且带路径信息', async () => {
  const { routes } = mountHost();
  const response = createFakeResponse();
  await routes[0].handler(createFakeRequest('GET', PREFIX + '/nope'), response);
  assert.equal(response.record.status, 404);
  assert.match(response.json().error, /nope/);
});

test('卸载时路由会被回收', () => {
  const { routes, disposers } = mountHost();
  assert.equal(routes.length, 1);
  assert.equal(disposers.length, 1);
  disposers[0]();
  assert.equal(routes.length, 0, 'dispose 后不应残留路由');
});

test('uptimeMs 使用注入的时钟，便于确定性测试', () => {
  let clock = 1000;
  const state = createDemoState({ now: () => clock });
  clock = 4000;
  assert.equal(state.snapshot().uptimeMs, 3000);
  assert.equal(state.hit(), 1);
  assert.equal(state.snapshot().hits, 1);
});

test('畸形 URL 不会抛异常（退回根路径）', async () => {
  const { routes } = mountHost();
  const response = createFakeResponse();
  await routes[0].handler(createFakeRequest('GET', 'http://[::bad'), response);
  assert.ok([200, 404].includes(response.record.status));
});
