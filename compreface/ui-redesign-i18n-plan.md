# CompreFace 控制台 UI 美化与中英国际化方案

> 对象：`mediation-deploy/compreface/build/CompreFace/ui`（CompreFace 1.2.0 官方 Web 控制台，Angular ~11.0.5 + Angular Material ^11.0.3）
> 目标：① 视觉与体验现代化；② 中/英双语支持。**不改变任何后端契约与业务逻辑**。
> 配套原型：`mediation-deploy/compreface/ui-prototype/index.html`（零依赖单文件，直接浏览器打开）。

---

## 一、现状分析

### 1.1 技术栈与结构（实读结论）

| 维度 | 现状 |
|---|---|
| 框架 | Angular ~11.0.5 + Material/CDK ^11.0.3，NgRx 10 全家桶 |
| 样式 | Material 自定义主题（`src/styles/custom-theme.scss`）+ 全局 SCSS（`src/styles.scss` 覆盖大量 `.mat-*` 类），色板集中在 `src/styles/colors.scss`，字体 **Poppins（Google Fonts 在线加载）** |
| 页面 | 登录 / 注册 / 应用列表（Dashboard）/ 应用详情（服务列表 + API key）/ 模型详情（统计图表）/ 测试服务（拖拽上传 + JSON 结果）/ 创建向导（MatStepper）/ 人脸库管理 / 密码恢复；用户管理为对话框族 |
| i18n | **框架已就位**：`@ngx-translate/core@13` + http-loader，43 个模板全部用 `\|\| translate }}` 管道；但**仅有 `src/assets/i18n/en.json`（14KB），无中文包，无语言切换入口** |
| 缺口 | 无暗色模式；Poppins 依赖 Google Fonts（**墙内部署会加载失败回退系统字体**）；登录页为唯一非 Material 风格页；部分列表无空态设计；对话框圆角 25px 过重、阴影杂乱 |

### 1.2 主要体验问题

1. **视觉**：Material v11 默认质感 + 25px 超圆角对话框 + 多种阴影混用，观感陈旧；卡片/描边/层级语言不统一。
2. **信息架构**：应用详情页 API key、服务类型、统计信息平铺，缺主次；测试页把原始 JSON 直接甩给用户。
3. **国际化**：无中文、无切换器；en.json 键结构良好（common/login/toolbar/applications/model_info…），补齐成本低。
4. **墙内适配**：Poppins 走 Google Fonts，受限网络下不可靠（与本部署件「不依赖被墙外网」原则冲突）。

---

## 二、设计系统（Design Tokens）

> 原则：中性底色 + **单一低饱和强调色**（青绿 Teal，呼应「核验/信任」语义，饱和度 < 80%）；
> 仪表盘类界面禁用衬线字体；圆角、阴影、间距全站归一。原型中已按此实现。

| Token | 值 | 用途 |
|---|---|---|
| `--bg` | `#F7F8FA` | 页面底（冷灰，非纯白非暖灰） |
| `--surface` | `#FFFFFF` | 卡片/面板 |
| `--line` | `#E5E8EC` | 1px 分隔线（优先于卡片阴影） |
| `--ink` / `--ink-2` / `--ink-3` | `#1B1F24` / `#5B6470` / `#98A1AC` | 主文 / 次文 / 弱文 |
| `--accent` | `#0F766E`（hover `#0C635C`） | 主按钮、活动态、焦点环、品牌 |
| `--ok` / `--warn` / `--danger` | `#15803D` / `#B45309` / `#BE4B48` | 状态点/结果语义色 |
| 圆角 | 容器 16px、控件 10px、对话框 20px（替换现 25px） | 统一圆角语言 |
| 阴影 | 仅一种：`0 12px 32px -18px rgba(27,31,36,.18)`（带底色调性，非黑） | 悬浮层级才用 |
| 字体 | **自托管** `Geist`/`Manrope`（或系统栈 `-apple-system, "Segoe UI", "PingFang SC", "Microsoft YaHei"`）+ 数字/JSON 用 `JetBrains Mono` | 替换在线 Poppins |
| 间距 | 4pt 网格；页面最大宽 1400px 居中 | — |

---

## 三、视觉风格与布局调整（按页面）

### 3.1 全局框架
- 顶栏：56px，白底 1px 底线；左侧 logo（SVG，不用位图）；右侧 **语言切换器（EN/中文）** + 用户菜单。
- 侧边导航：保留可折叠（200/64px），项高 40px、选中态用 3px 强调色左条 + 浅青底（替代 Material 默认 ripple 满铺）。
- 全局把 Material 主题色替换为新 Token（改 `custom-theme.scss` 的 `$primary/$accent` + `colors.scss` 即可全局生效，**无需逐组件改**）。
- 对话框：圆角 25px→20px、去多重阴影、标题/内容/操作区间距归一（`styles.scss` 统一覆盖）。

### 3.2 登录页（唯一非 Material 页，重做收益最高）
- 改为**左右分屏**（非居中卡片）：左 45% 品牌区（深色 `#101418` 底 + 细网格纹理 + 三条隐私要点：仅 1:1 核验 / 不建人脸底库 / 不持久化向量），右 55% 表单区。
- 表单改 Material 风格：label 上置、错误内联、按钮全宽、loading 用按钮内 spinner。
- 右下角保留 build 版本号（现有信息，重新排版）。

### 3.3 应用列表（Dashboard）
- 搜索 + 创建按钮一行；卡片网格 3 列（≤lg 2 列、≤md 1 列）。
- 卡片内容重构：应用名（主）、服务类型徽标（VERIFY / DETECTION 彩点 + 文案）、创建时间、`requests(24h)` 单指标；卡片 hover 抬升 2px + 边框转强调色。
- **补空态**：搜索无结果/无应用时给插画式空态（SVG + 引导按钮），替代现在的空白网格。

### 3.4 应用详情（服务列表）
- 页头：面包屑 + 应用名 + 重命名/删除图标按钮（保留现有能力）。
- **API key 行**改为独立「密钥条」：等宽字体、默认掩码（`00c8…d43c`）、一键复制（复制成功打勾反馈 1.5s）、显隐切换。
- 服务卡片：类型徽标 + 状态呼吸点（alive）、24h 请求数、p95 延迟、进入「测试」入口；统计图表（chart.js）下沉到模型详情页，不与列表抢层级。

### 3.5 测试服务页
- 左右结构：左侧上传区（拖拽 + 点击，实线强调色虚线框，含格式提示），右侧结果区。
- 结果用**环形相似度仪表** + 语义结论（同人/不同人 + 置信色），替代直接甩 JSON；JSON 收进「请求/响应」折叠面板（保留现有排障能力）。
- 上传中用**骨架屏**（匹配结果区尺寸），不用转圈 spinner。
- 注：本部署件网关只放行 detection/verification，测试页的人脸库入口（recognition）应按 `EXTRA_PLUGINS`/服务类型同样隐藏（与 side-menu 现有 `*ngIf type===recognition` 一致）。

### 3.6 组件级美化清单
| 组件 | 改动 |
|---|---|
| 按钮 | 主/次/幽灵三态；`:active` 下压 `translateY(1px)`；loading 态内嵌 spinner |
| 输入框 | 统一 10px 圆角、focus 焦点环（2px accent/30%）、错误内联文案 |
| 表格（MatTable） | 去斑马纹，用 1px 行线；表头小号大写字距；数字右对齐等宽字体 |
| 徽标/状态 | 统一「彩点 + 文案」，语义色用 Token |
| 对话框族 | create/edit/delete/confirm 统一标题区、按钮右对齐、危险操作主按钮用 danger 色 |
| 拖拽区 | 虚线框 + 拖入高亮 + 缩略图预览 |
| 图表（ng2-charts） | 去网格噪声，强调色单色阶，tooltip 跟 Token |
| 空态/加载态 | 全站统一空态插画组件 + 骨架屏组件（新增 2 个公共组件） |

---

## 四、中英国际化方案（改动小、收益大）

### 4.1 机制（复用现有 @ngx-translate，不引新框架）
1. **新增语言包** `src/assets/i18n/zh-CN.json`：键结构与 `en.json` 完全对齐（14KB、约 40+ 命名空间），补全所有缺失键的英文回退。
2. **语言切换器**：顶栏右侧 `EN / 中文` 分段控件；调用 `translate.use(lang)` 即时切换（ngx-translate 天然支持热切换，模板无需改动）。
3. **持久化 + 回退**：`localStorage['cf_lang']` 记忆选择；`AppModule` 初始化时 `translate.setDefaultLang('en')` + `translate.use(saved || browserLang)`；`zh-CN.json` 缺键自动回退英文（增量翻译不阻塞上线）。
4. **文案管理规范**：
   - 键命名空间沿用现有约定（`login.*`、`applications.*`、`side_menu.*`、`model_info.*`…），新增页面键进对应命名空间；
   - **模板继续零硬编码**（现状已达标，纳入 ESLint 检查：自定义规则扫描模板中的中文/英文裸文案）；
   - 中文文案统一简体、技术名词（API Key、VERIFY）不翻译；数字/代码一律等宽字体不随语言切换变形。
5. **切换器组件**：新增 `features/language-switcher`（含 `LanguageService`：读/写 localStorage + 调 translate.use + 更新 `<html lang>`）。
6. **Date/数字本地化**：`LOCALE_ID` 注册 `zh-CN`，日期管道跟随语言（创建时间等）。

### 4.2 工作量与分期
| 期 | 内容 | 预估 |
|---|---|---|
| P0（半天） | zh-CN.json 全量翻译 + 语言切换器 + localStorage 持久化 + LOCALE_ID | 纯增量，零风险 |
| P1（1–2 天） | 设计 Token 落地：`colors.scss`/`custom-theme.scss`/`styles.scss` 三文件改主题 + 对话框/按钮/表格全局覆盖 | 全站观感立即统一 |
| P2（2–3 天） | 登录页重做、应用列表/详情信息架构重构、空态与骨架屏组件、测试页相似度仪表 | 按原型逐页对齐 |
| P3（可选） | 暗色模式（Token 已变量化，加一组 `[data-theme=dark]` 即可）、字体自托管（墙内） | — |

### 4.3 墙内注意
- Poppins（Google Fonts）必须替换：自托管 woff2 放 `src/assets/fonts/`，或改系统字体栈（原型采用系统栈，生产建议自托管 Manrope/Geist）。
- 不新增任何运行时 CDN 依赖。

---

## 五、原型说明（ui-prototype/index.html）

- **零依赖单文件**，浏览器直接打开即可演示；还原 Angular 版的信息结构与交互，用于评审视觉方向与文案，不承载生产代码。
- 覆盖：登录（分屏 + 错误态）→ 应用列表（空态/搜索过滤）→ 应用详情（密钥掩码复制）→ 测试服务（模拟上传骨架屏 → 相似度仪表动画 → 语义结论）。
- 右上角 **EN/中文** 即时切换全部文案（与 §4.1 机制同构：字典 + data-i18n，等价于 ngx-translate 的 `translate.use()`）。
- 演示数据为虚构（应用名/请求数/延迟），相似度演示值取自本部署件实测口径（同人 0.919 / 异人 0.078）。

### 落地到 Angular 的映射
| 原型 | Angular 落点 |
|---|---|
| 语言切换 | `features/language-switcher` + `zh-CN.json`（translate.use） |
| Token | `styles/colors.scss` + `custom-theme.scss` + `styles.scss` |
| 登录分屏 | `pages/login` + `features/login-form` 模板重排 |
| 密钥条 | `features/model-info/model-info.component.html`（已有 cdkCopyToClipboard，加掩码/显隐） |
| 相似度仪表 | `pages/test-model` + `features/face-services` 结果组件替换裸 JSON |
| 空态/骨架屏 | 新增 `features/empty-state`、`features/skeleton` 公共组件 |
