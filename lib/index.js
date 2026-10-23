/**
 * dsh-demo-plugin —— 宿主（Node）半侧
 *
 * 只做一件事：注册一个 HTTP 接口，供界面半侧（lib/client.js）调用。
 *   GET /dsh-demo-plugin/hello   返回 消息 / 点击次数 / 已运行时长 / 宿主时间 / Node 版本
 *
 * 这是最干净的最小骨架：
 *   - 没有第三方依赖（只用 Node 内置能力）
 *   - 纯 ESM，不需要打包编译
 *   - 所有副作用都塞进 ctx.effect()，插件卸载时自动回收
 */

/** 稳定插件名，必须与 package.json 的 name 一致。 */
export const name = 'dsh-demo-plugin';

/** 接口前缀；改这里记得同步改 lib/client.js 的 API 常量。 */
export const PREFIX = '/dsh-demo-plugin';

function json(response, status, payload) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  response.end(JSON.stringify(payload));
}

/**
 * 插件的内存状态。抽成独立函数是为了能在测试里注入假时钟。
 * @param {{ now?: () => number }} [options] - 可选注入的时钟。
 * @returns {{ hit: () => number, snapshot: (extra?: object) => object }}
 */
export function createDemoState(options = {}) {
  const now = typeof options.now === 'function' ? options.now : () => Date.now();
  const startedAt = now();
  let hits = 0;
  return {
    /** 记录一次点击，返回累计次数。 */
    hit() {
      hits += 1;
      return hits;
    },
    /** 生成一屏给前端看的数据。 */
    snapshot(extra = {}) {
      const at = now();
      return Object.assign({
        ok: true,
        message: '插件跑起来啦 👋',
        hits,
        uptimeMs: Math.max(0, at - startedAt),
        serverTime: new Date(at).toISOString(),
        node: process.version,
      }, extra);
    },
  };
}

/**
 * 生成 HTTP handler。独立出来的目的是让测试可以不启动真实服务器就覆盖全部分支。
 * @param {object} state - createDemoState() 的返回值。
 * @param {object} [logger] - 宿主的 logger，可为空。
 * @returns {(request: object, response: object) => Promise<void>}
 */
export function createHandler(state, logger) {
  return async function handler(request, response) {
    let pathname = '/';
    try {
      pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
    } catch {
      // URL 畸形时退回根路径，不让插件抛异常影响宿主。
    }
    const sub = pathname.startsWith(PREFIX) ? (pathname.slice(PREFIX.length) || '/') : pathname;
    const method = (request.method || 'GET').toUpperCase();

    if (method !== 'GET') {
      return json(response, 405, { ok: false, error: '这个演示接口只支持 GET' });
    }
    if (sub === '/' || sub === '/hello') {
      state.hit();
      const payload = state.snapshot({ endpoint: PREFIX + '/hello' });
      logger?.debug?.('demo-plugin: hello #' + String(payload.hits));
      return json(response, 200, payload);
    }
    return json(response, 404, { ok: false, error: '没有这个接口：' + sub });
  };
}

/**
 * 宿主插件入口。
 * @param {object} ctx - Cordis 插件上下文。
 */
export function apply(ctx) {
  const state = createDemoState();
  ctx.inject(['webServer'], (hostCtx) => {
    hostCtx.effect(
      () => hostCtx.webServer.register({
        kind: 'prefix',
        path: PREFIX,
        handler: createHandler(state, ctx.logger),
      }),
      'demo-plugin: routes',
    );
  });
  ctx.logger?.info?.('demo-plugin: 已加载，接口 ' + PREFIX + '/hello');
}
