# TODO: Upstream PR #77 Comparison & Feature Gap

本文件记录 upstream [PR #77](https://github.com/HeZeBang/TechPie-flutter/pull/77) (`feat: add ai support` by HeZeBang) 中已实现、但当前 `codex/genai-foundation` 分支尚未具备的功能与设计点，供后续演进和架构融合参考。

---

## 1. 校园数据 Agent 与工具调用（Tool / Function Calling）

* **PR #77 现状**：
  * 在 `lib/services/ai_tools.dart` 中构建了基于模型的只读工具集（`buildAiTools`），通过 `flutter_ai_tools` 暴露给 LLM，支持多轮自动工具执行循环（Tool Execution Loop，上限 8 步）：
    1. `get_current_time`：获取当前 ISO 时间、星期几、以及基于学期开学日计算的**当前教学周**（`scheduleService.currentWeek()`）。
    2. `get_semesters`：获取可用学期列表及当前选中学期（基于 eGate 绑定与本地缓存）。
    3. `get_week_schedule`：按学期与周次查询课表，返回按周一至周日分组的课程、节次、时间段、教室与教师信息。针对非当前学期支持缓存优先与周数推导。
    4. `get_assignments`：查询全平台（Blackboard、考试系统、Gradescope、Hydro）的作业与考试截止日期，支持平台与类型过滤，自动排除本地隐藏项。
  * System Prompt 明确引导模型在面对日程、作业、周次提问时主动调用工具，并处理未绑定 eGate 的错误引导。
* **当前分支缺失**：
  * `codex/genai-foundation` 聚焦于上科大官方 GenAI 平台的端到端接入（流式对话、文生图、用量查询），目前为纯文本/思维链对话，**尚无客户端 Agent 工具调用能力**，无法回答用户关于个人课表、作业的个性化校园数据提问。
* **规划与建议**：
  * 在 `lib/features/genai/application/` 中引入工具调度层（或当接入支持 Tool Calling 的模型时），复用 `ScheduleService` 和 `AssignmentService`，将课表与作业数据作为可选 Tools 注入给对话引擎。

---

## 2. 自定义与第三方模型配置（BYOK - Bring Your Own Key）

* **PR #77 现状**：
  * 提供了完整的自定义 API 配置页面（`AiConfigPage`）与模型实体（`AiConfig`）：
    * 支持自定义 `baseUrl`（带 `/v1` 自动规整逻辑 `normalizeAiBaseUrl`）。
    * 支持自定义 API 令牌（`authToken`，存入 Secure Storage）。
    * 支持自定义模型名称（`model`，默认配置为 DeepSeek 的 Anthropic 兼容端点 `deepseek-v4-flash`）。
    * 支持调节 System Prompt、Temperature（0.0 ~ 2.0）以及 Max Tokens（默认 2048）。
  * 提供了快捷配置引导 Banner（未填 Token 时显示引导入口，禁用输入框并提供“前往配置”按钮）。
* **当前分支缺失**：
  * `codex/genai-foundation` 严格绑定上科大官方 GenAI 平台（`genai.shanghaitech.edu.cn/htk/`），依赖学校统一身份认证（IDS SSO）；**不支持配置商用 API Key（如 OpenAI / DeepSeek / Claude / 自建端点）**。
* **规划与建议**：
  * 考虑未来支持多 Provider 架构：
    * 默认/推荐模式：使用现有的“校园 GenAI”（免配置、免付费、使用校内算力与官方模型池）。
    * 高级模式：允许用户切换为“自定义 API Key”（BYOK），接入外部更强或专有的商业模型，同时复用相同的聊天 UI 与工具系统。

---

## 3. 预置提示词模板画廊（Prompt Template Gallery）

* **PR #77 现状**：
  * 在 `lib/models/ai_chat.dart` 中内置了常用提示词画廊数据 `aiPromptGallery`，并在 `lib/pages/ai_gallery_page.dart` 中提供分类卡片展示：
    * 翻译 英文 → 中文
    * 翻译 中文 → 英文
    * 总结摘要（无序列表要点提取）
    * 润色改写（学术/专业语调）
    * 解释代码（逐行讲解与潜在问题分析）
    * 制定学习计划
    * 撰写正式邮件
    * 头脑风暴（创意发散）
  * 点击模板可新建会话并将模板文本填入输入框，光标自动落至末尾。
* **当前分支缺失**：
  * `codex/genai-foundation` 仅有空白输入框，缺乏新用户引导与常用学习/科研场景的快捷 Prompt 模板。
* **规划与建议**：
  * 在 `lib/features/genai/presentation/` 的空白会话区或工作区菜单中，加入类似的学术/日常模板快捷入口。

---

## 4. 代码高亮与富文本增强（Code Syntax Highlighting）

* **PR #77 现状**：
  * 引入了 `package:highlight`，在 `widgets/ai/ai_code_highlighter.dart` 中实现了纯 Dart 的代码语法高亮。
  * 代码块支持语言标签显示、一键复制到剪贴板，并适配暗色/亮色主题。
  * 注册了 `AiThemeExtension`，将代码背景色、高亮对比度与 TechPie 的 `ColorScheme`（`surfaceContainerHighest` / `onSurface`）精准对齐。
* **当前分支缺失**：
  * `codex/genai-foundation` 目前采用基础的 `flutter_markdown`，代码块仅做基本等宽字体和背景框展示，**缺乏语言级代码高亮（如 Dart, Python, C++, SQL 等语法着色）**。
* **规划与建议**：
  * 在 `flutter_markdown` 的 `MarkdownElementBuilder` 中集成轻量级语法着色器，提升科研与编程答疑体验。

---

## 5. 对话流与交互体验（Regenerate、自动命名与主题扩展）

* **PR #77 现状**：
  * **重新生成（Regenerate）**：支持发送空文本触发重新生成，自动回退上一轮 Assistant 输出并重新请求。
  * **首句自动提炼标题**：新会话标题默认为“新对话”，首轮发送后自动根据用户首条输入前缀提炼并更新标题（`_deriveTitle`）。
  * **主题扩展（AiThemeExtension）**：通过 Material 3 ThemeExtension 机制下发 AI 专属颜色，避免了硬编码颜色造成的暗黑模式适配问题。
* **当前分支缺失**：
  * `codex/genai-foundation` 的标题主要依赖服务端记录或默认 ID；重新生成机制尚未在 UI 层形成便捷按钮；UI 颜色多为直取 `Theme.of(context).colorScheme`。
* **规划与建议**：
  * 为 Assistant 气泡增加“重新生成”与“复制”快捷操作栏。
  * 对本地暂存或新创建的会话引入首句自动截取标题逻辑。

---

## 6. 交互式组件演示页（Interactive Demo Showcase）

* **PR #77 现状**：
  * 在 `lib/pages/ai_demo/` 中构建了一套完整的独立演示体系（`AiDemoPage`、`DemoProvider`、`DemoTools`、`FeatureSections`）：
    * 模拟流式打字效果与速度控制。
    * 工具调用（Tool Call & Tool Result）的可视化展示。
    * 复杂 Markdown（表格、引用、数学公式、嵌套列表）的渲染展示。
    * 错误恢复与重试逻辑的直观交互。
* **当前分支缺失**：
  * `codex/genai-foundation` 拥有非常完善的自动化单元测试与 Chrome 端到端流式测试（80+ 测试用例），但在应用内缺乏一个对设计师/开发者友好的纯组件交互 Playground。
* **规划与建议**：
  * 可在 debug 模式下增加一个简单的 UI 橱窗，方便预览思维链折叠、代码块渲染与文生图状态。
