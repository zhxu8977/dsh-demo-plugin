/**
 * dsh-demo-plugin —— 客户端（Web 界面）半侧
 *
 * 手写的懒加载 CJS bundle：脚本执行时只注册工厂，真正的副作用
 * （注入样式、注册插槽）发生在工厂被 materialize 之后。
 *
 * 干的活：在侧边栏底部“头像上方”那一行加一个 👋 按钮，
 * 点一下向宿主请求 /dsh-demo-plugin/hello，并用浮层卡片展示返回结果。
 */

window.__ModuleLoader__.load({
  id: "dsh-demo-plugin",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const react = require("react");
    const h = react.createElement;

    /** 只依赖插槽服务；别的服务缺了也不至于整个插件不加载。 */
    const inject = ["slots"];
    const API = "/dsh-demo-plugin";

    /* ---------------------------------------------------------------- 样式 */
    const CSS = `
.demo-btn { width: 34px; height: 34px; display: grid; place-items: center; padding: 0; border: 0;
  border-radius: 9px; background: transparent; color: var(--dsw-alias-label-secondary, #747b86);
  cursor: pointer; font: inherit; font-size: 16px; line-height: 1; }
.demo-btn:hover { color: var(--dsw-alias-label-primary, #17191c);
  background: var(--dsw-alias-interactive-bg-hover, rgba(127,127,127,.14)); }
.demo-btn[data-spin="true"] { animation: demo-fade 1s ease-in-out infinite; }
@keyframes demo-fade { 50% { opacity: .45; } }
.demo-mask { position: fixed; inset: 0; z-index: 90; display: grid; place-items: center;
  background: rgba(8,10,14,.55); }
.demo-card { width: min(360px, 90vw); padding: 20px 22px; border-radius: 14px;
  font-family: var(--dsw-font-family, inherit); color: var(--dsw-alias-label-primary, #17191c);
  background: var(--dsw-alias-bg-layer-2, #fff);
  border: 1px solid var(--dsw-alias-border-l1, rgba(127,127,127,.28));
  box-shadow: 0 24px 60px rgba(0,0,0,.35); }
.demo-card h3 { margin: 0 0 10px; font-size: 15px; font-weight: 650; }
.demo-card dl { display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; margin: 0; font-size: 13px; }
.demo-card dt { color: var(--dsw-alias-label-secondary, #747b86); }
.demo-card dd { margin: 0; font-variant-numeric: tabular-nums; }
.demo-card .demo-actions { display: flex; justify-content: flex-end; margin-top: 16px; }
.demo-card button.demo-close { height: 32px; padding: 0 14px; border-radius: 9px; cursor: pointer;
  font: inherit; font-size: 13px; color: var(--dsw-alias-label-primary, #17191c);
  background: var(--dsw-alias-interactive-bg-hover, rgba(127,127,127,.16));
  border: 1px solid transparent; }
.demo-card button.demo-close:hover { border-color: var(--dsw-alias-border-l1, rgba(127,127,127,.3)); }
.demo-err { margin: 12px 0 0; font-size: 12px; color: #d33; }
`;

    function installStyles() {
      if (typeof document === "undefined") return () => {};
      if (document.querySelector('style[data-plugin="dsh-demo-plugin"]') !== null) return () => {};
      const tag = document.createElement("style");
      tag.dataset.plugin = "dsh-demo-plugin";
      tag.textContent = CSS;
      document.head.appendChild(tag);
      return () => { tag.remove(); };
    }

    /* ---------------------------------------------------------------- 状态 */
    let panel = { open: false, loading: false, error: "", data: null };
    const listeners = new Set();
    const subscribe = (listener) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
    const getSnapshot = () => panel;
    const setPanel = (patch) => {
      panel = Object.assign({}, panel, patch);
      for (const listener of Array.from(listeners)) listener();
    };
    const usePanel = () => react.useSyncExternalStore(subscribe, getSnapshot, getSnapshot);

    /** 向宿主要一次数据并打开浮层。 */
    async function openPanel() {
      setPanel({ open: true, loading: true, error: "" });
      try {
        const response = await fetch(API + "/hello?t=" + String(Date.now()), { cache: "no-store" });
        const payload = await response.json();
        if (payload.ok !== true) throw new Error(payload.error || "HTTP " + String(response.status));
        setPanel({ loading: false, data: payload });
      } catch (error) {
        setPanel({ loading: false, error: String(error && error.message ? error.message : error) });
      }
    }

    const fmtTime = (iso) => {
      try { return new Date(iso).toLocaleString(); } catch { return String(iso); }
    };
    const fmtUptime = (ms) => {
      const seconds = Math.max(0, Math.round(Number(ms) / 1000));
      if (seconds < 60) return seconds + " 秒";
      return Math.floor(seconds / 60) + " 分 " + (seconds % 60) + " 秒";
    };

    /* ---------------------------------------------------------------- 组件 */
    function DemoButton() {
      const snap = usePanel();
      return h("button", {
        type: "button",
        className: "demo-btn",
        title: "演示插件：点一下试试",
        "aria-label": "演示插件",
        "data-spin": snap.loading === true ? "true" : undefined,
        onClick: () => { void openPanel(); },
      }, "👋");
    }

    function DemoPanel() {
      const snap = usePanel();
      if (snap.open !== true) return null;
      const data = snap.data;
      const rows = [
        ["消息", data === null ? (snap.loading ? "正在问宿主…" : "—") : data.message],
        ["点击次数", data === null ? "—" : String(data.hits)],
        ["已运行", data === null ? "—" : fmtUptime(data.uptimeMs)],
        ["宿主时间", data === null ? "—" : fmtTime(data.serverTime)],
        ["Node", data === null ? "—" : String(data.node)],
      ];
      return h("div", {
        className: "demo-mask",
        role: "presentation",
        onClick: () => { setPanel({ open: false }); },
      },
        h("div", {
          className: "demo-card",
          role: "dialog",
          "aria-modal": "true",
          "aria-label": "演示插件",
          onClick: (event) => { event.stopPropagation(); },
        },
          h("h3", null, "👋 演示插件已连通"),
          h("dl", null, rows.map((pair, index) => [
            h("dt", { key: "t" + String(index) }, pair[0]),
            h("dd", { key: "d" + String(index) }, pair[1]),
          ])),
          snap.error === "" ? null : h("p", { className: "demo-err" }, "请求失败：" + snap.error),
          h("div", { className: "demo-actions" },
            h("button", { type: "button", className: "demo-close", onClick: () => { setPanel({ open: false }); } }, "关闭"),
          ),
        ),
      );
    }

    /* ---------------------------------------------------------------- 挂载 */
    function apply(ctx) {
      ctx.effect(() => installStyles(), "demo-plugin: styles");
      ctx.slots.inject("sidebar.footer.action", () => ctx.slots.register({
        name: "sidebar.footer.action",
        id: "demo-plugin",
        order: 40,
      }, DemoButton));
      ctx.slots.inject("shell.overlay", () => ctx.slots.register({
        name: "shell.overlay",
        id: "demo-plugin",
        order: 40,
      }, DemoPanel));
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  },
});
