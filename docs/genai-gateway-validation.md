# GenAI 网关修复与验收

2026-10-28，已同步本地上游 `b517039`，以及其工作区的原生工具增量、空回复重试更新。对照 `/proj/GenAI2OpenAI/docs/TechPie工具链问题交接.md`。

## 已修复

- 先接收最后一段正文，再处理结束原因。保留 `length`、`content_filter`；没有 finish 或 DONE 的 EOF 返回错误。
- 工具解析支持标准对象、嵌套 function、顶层数组、尾随链接、多个 JSON 对象、多个 XML 块。保留全部调用及已有 ID。
- 工具名称必须在本次声明中，arguments 必须能解析为 JSON 对象。只在上游正常结束、调用及参数已完整时补齐外层数组或唯一 tool_calls 包装对象的闭合符；不补调用、参数、字符串或逗号后缺失的值。未知工具、错误参数不回退成成功正文。普通 name 字段、字段说明和空 tool_calls 数组保留为普通答案。这里不做完整 JSON Schema 校验。
- 支持 Responses 的函数工具定义、function_call / function_call_output 历史、函数输出和 SSE added/delta/done/completed 生命周期。截断为 incomplete，错误为 failed。
- 补充执行任务时应当返回工具调用的提示，落实 required 和指定函数；auto 仍允许正常总结。仅在上游正常结束且正文和原生工具调用均为空时，使用相同历史重试一次；首轮纯推理不向客户端发布。两次均为空时报错。错误、EOF、length、已输出正文或工具调用均不重试，不重放工具副作用。
- Chat 优先采用 max_completion_tokens，其次 max_tokens；Responses 使用 max_output_tokens。
- 原生 tool_calls 按 index 聚合名称及参数分片，兼容 message 和旧 function_call 字段，聚合后统一校验名称及参数；未启用工具时不接收原生调用。
- SSE 在等待上游响应头时发送心跳，客户端断开时取消等待并关闭对应上游连接。
- 请求日志前缀 `genai_request`。只记录请求 ID、路径、模型、计数、tool_choice、输出上限、耗时、结束原因、DONE、取消状态、异常类别，不记录凭据、正文或工具结果。`saw_done=false` 表示本次没有读到 DONE；已有 finish_reason 时也正常结束读取。

## 拆分前的整包验证

以下记录来自 PR #135 的本机安装与整包测试，包含 Linux DDL、手表等模块。本 PR 仅保留 GenAI 网关、功能页和对应测试。

- `flutter test test/genai_gateway_test.dart --no-pub`：62 项通过。
- `flutter test --no-pub`：全套 740 项通过；更新了截止日期空状态断言，以及设置页日志入口的滚动定位。
- 对修改的 Dart 文件定向运行 `flutter analyze --no-pub`：无问题。
- `flutter build linux --release --no-pub`：成功。
- `tool/genai_gateway_smoke.dart`：真实 ChatGLM，在 Chat Completions 和 Responses 上分别完成流式请求工具、夹具返回、非流式总结；开发网关和安装版各验证一次。只提供 fixture_read 夹具，结果为固定编号，没有执行文件或 Git 操作，没有测试 GPT。
- 安装路径：`/home/jdz/.local/opt/techpie-linux-widgets-v1/bundle`。
- 本轮安装进程 PID 404337，`127.0.0.1:5000` 属于该进程；核对其加载的 libapp.so 与构建产物一致。
- libapp.so SHA256：`41666b4dfccc439d6d1622a0f084f4d8816766d204fa11f061cb06e068b7510d`。
- 上一版备份：`/home/jdz/.local/opt/techpie-linux-widgets-v1/bundle-backup-20261028-194654`。
- 本次通过 `techpie --genai-api` 恢复 API 服务。平常仍可从 GenAI API 页启动。

日志：

- `/tmp/techpie-all-sync-tests-final.log`
- `/tmp/techpie-genai-sync-tests.log`
- `/tmp/techpie-genai-sync-analyze.log`
- `/tmp/techpie-linux-build-sync.log`
- `/tmp/techpie-real-chatglm-sync.log`
- `/tmp/techpie-installed-chatglm-sync.log`
- `/tmp/techpie-installed-genai-sync.log`

## VS Code 原客户端

尚未完成原客户端的文件读取、编辑验收；本机无该会话的客户端工具记录。原截图的实际 API 路径和停止原因仍未确定。重测时，用请求日志中的 request_id、path、结束原因与客户端工具记录对应。不要以模型声称完成或界面步骤计数认定实际执行成功。
