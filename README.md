# dsh-demo-plugin

演示插件：在 DeepSeek Harness 侧边栏底部加一个 👋 按钮，点一下弹出卡片 —— 显示消息 / 点击次数 / 已运行时长 / 宿主时间 / Node 版本。

功能故意做到最小，但 `目录结构、单元测试、CI/CD 流水线、一键推送脚本` 都是真的，可以直接当模板改成你自己的插件。

---

## 一、它是怎么工作的

| 半侧 | 文件 | 干什么 |
|---|---|---|
| 宿主（Node） | `lib/index.js` | 注册一个 HTTP 接口 `GET /dsh-demo-plugin/hello`，返回上面那几个值 |
| 界面（Web） | `lib/client.js` | 往 `sidebar.footer.action` 插槽放按钮、往 `shell.overlay` 插槽放卡片 |
| 接线 | `cordis.patch.yml` | 告诉宿主"把这个插件挂进 profile" |

宿主接口可以直接用浏览器验证（桌面版默认端口 19387）：

```
http://127.0.0.1:19387/dsh-demo-plugin/hello
```

会看到类似：

```json
{"ok":true,"message":"插件跑起来啦 👋","hits":3,"uptimeMs":42000,"serverTime":"2026-10-23T09:12:00.000Z","node":"v24.18.0"}
```

---

## 二、目录结构

```
dsh-demo-plugin/
├─ package.json          # 名字、版本、dsh 字段（bundle + client 声明）
├─ cordis.patch.yml      # 把插件作为一行挂进 profile
├─ lib/
│  ├─ index.js           # 宿主半侧（纯 ESM，无需编译）
│  └─ client.js          # 界面半侧（手写懒加载 bundle）
├─ test/host.test.js     # 9 个单元测试，用假 ctx 跑，不依赖宿主
├─ .github/workflows/
│  ├─ ci.yml             # 每次推送自动跑检查和测试
│  └─ release.yml        # 打 tag 时自动打 zip + 建 Release
├─ scripts/
│  ├─ connect-github.ps1 # 首次连 GitHub（校验 token / 建仓库 / 推送，全自动）
│  ├─ setup-github.ps1   # 手动版首次配置（自己建好仓库时用）
│  ├─ push.ps1           # 一键提交 + 推送
│  ├─ release.ps1        # 一键发版
│  └─ new-plugin.ps1     # 拿这个当模板生成新插件
├─ connect.cmd           # 首次连 GitHub：粘 token → 自动建仓库 → 推送
├─ push.cmd  setup.cmd  release.cmd  install.cmd  new-plugin.cmd
└─ install.ps1           # 装进本机 profile（软链接）
```

---

## 三、先在本机装上看看（3 步）

1. 双击 `install.cmd`（会自动备份、写 profile、建软链接）
2. 重启 DeepSeek Harness（新增插件必须重启才会加载）
3. 看侧边栏底部、头像上方，出现 👋 按钮，点一下

- 只想看会改什么：`install.cmd -DryRun`
- 不想要了：`install.cmd -Uninstall`，再重启

---

## 四、日常开发

```bat
npm run verify        :: 语法检查 + 9 个测试（改完先跑这个）
```

- 改**宿主**（`lib/index.js`）→ 要重启应用才生效
- 改**界面**（`lib/client.js`）→ 浏览器刷新页面（Ctrl+R）就行
- 测试是纯函数的：不用启动宿主、不碰网络，秒级跑完

---

## 五、第一次推到 GitHub（只做一次，约 3 分钟）

**全程你只需要做一件事：生成一个 token。** 仓库会自动创建，不用你去 GitHub 点 New repository。

### 5.1 生成 token（唯一的"找东西"环节）

1. 打开 https://github.com/settings/tokens  （或者：右上角头像 → **Settings** → 左侧栏**拉到底** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**）
2. 右上 **Generate new token** → 选 **Generate new token (classic)**
3. **Note** 随便写，比如 `dsh-demo-plugin`
4. **Expiration** 选 **90 days**（到期重新生成一个就行）
5. 在 **Select scopes** 里勾两个**大项**：
   - ☑ **repo**（勾上整块，带一堆子项是正常的）
   - ☑ **workflow**（不勾的话，推不上去 `.github/workflows` 里的流水线文件）
6. 拉到页面最下面点绿色 **Generate token**
7. 页面顶部出现 `ghp_xxxxxxxx...` —— **只显示这一次**，点复制

> token 就是"给程序的密码"，不是你的登录密码。它只在你设的 90 天里有效，随时能在同一页面删除。

### 5.2 双击 connect.cmd

1. 双击 `connect.cmd`
2. 提示 `token` 时，**右键粘贴**（或 Ctrl+V），回车
   - 屏幕不会显示任何字符，这是正常的
3. 看着它跑：验证 token → 建仓库 → 配远程 → 首次提交 → 推送

token 被存进 **Windows 凭据管理器**，不会写进仓库、不会留明文文件，也不用发给我。

### 5.3 看流水线

脚本最后会打印两个地址：

- 仓库：`https://github.com/你的用户名/dsh-demo-plugin`
- 流水线：`.../actions` —— 点进去看到 CI 绿色对勾，说明自动化跑通了

### 5.4 不想用自动脚本？（手动路线）

`setup.cmd` 是手动版：自己建空仓库，然后把用户名 / 邮箱 / 仓库地址填进去。两条路最后效果一样。

---

## 六、以后每次改完代码

```bat
push.cmd "改了按钮颜色"
```

三步全自动：`git add` → `git commit` → `git push`，然后 GitHub Actions 自动跑测试。

---

## 七、发版（自动打包 + 自动写 Release）

```bat
release.cmd 0.2.0
```

它自动完成：改 `package.json` 版本号 → 提交 → 打 tag `v0.2.0` → 推送 → GitHub Actions 跑测试 → 打 zip → 创建 Release。
别人在 **Releases** 页面点一下就能下载 zip。

---

## 八、流水线到底干了什么

| 工作流 | 触发时机 | 做什么 |
|---|---|---|
| `ci.yml` | 每次推到 main / 每个 PR / 手动点 | Node 20 + 22 两套环境跑语法检查和 9 个测试，再自检 package.json 关键字段 |
| `release.yml` | 推 `v*` tag | 先跑一遍测试（不过就不发）→ 打 zip → 创建 Release + 自动生成变更说明 |

免费额度：**公开仓库无限**，私有仓库 2000 分钟/月；这套每次跑不到 1 分钟。

---

## 九、常见问题

| 现象 | 处理 |
|---|---|
| 按钮没出现 | 重启应用（新插件必须重启）；再看 `install.cmd -DryRun` 有没有建软链接 |
| push 卡住问密码 | 填 username + token（不是登录密码） |
| 提示 `remote origin already exists` | 不用管，`setup.cmd` 会自动改地址 |
| Actions 红叉 | 点进失败的 step 看日志；本地先跑 `npm run verify` 复现 |
| 想改接口路径 | 同时改 `lib/index.js` 的 `PREFIX` 和 `lib/client.js` 的 `API` |
| 中文乱码 | 所有文件都是 UTF-8；`.cmd` 里已经 `chcp 65001` |
| 提示 `token 无效或已过期` | 重新去 https://github.com/settings/tokens 生成一个；注意复制完整（以 `ghp_` 开头） |
| 提示 `连不上 GitHub` | 网络/代理问题：确认代理软件开着（本机走 127.0.0.1:7890） |
| 提示缺少 `workflow` 权限 | 那个 token 勾权限时漏了 workflow；重新生成并勾上 |
| 仓库建好了但没东西 | 回到脚本日志看 `git push` 那一步；也可以直接重跑 connect.cmd（重复跑是安全的） |
| 忘了 token 存在哪 | Windows「凭据管理器」→ Windows 凭据 → 找 `git:https://github.com` |

---

## 十、安全须知

- token 等于密码，**不要**写进代码、不要提交到仓库
- `.gitignore` 已经挡住 `.env` / `*.key` / `*.pem` / `secrets*.json`
- 如果不小心把 token 提交了：立刻去 GitHub 删掉这个 token 重新生成

---

## License

MIT
