const TIMEOUT_MS = 15000;
const NETWORK_MESSAGE = "网络连接失败，请检查网络后重试";
const timeoutMessage = (action) =>
  action === "create"
    ? "请求超时，提交结果尚未确认，请勿连续重复提交"
    : "请求超时，请稍后重试";
function withTimeout(action, run) {
  let timer;
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(timeoutMessage(action)));
      if (controller) controller.abort();
    }, TIMEOUT_MS);
  });
  const work = Promise.resolve().then(() => run(controller));
  return Promise.race([work, timeout]).finally(() => clearTimeout(timer));
}
export async function api(action, data = {}) {
  const endpoint =
    location.hostname === "techpie-feedback.dzhes.app" ||
    location.hostname === "localhost"
      ? "/api/feedback"
      : "https://techpie-feedback.dzhes.app/api/feedback";
  let result;
  try {
    // No automatic retry: create must not risk duplicate submissions.
    const outcome = await withTimeout(action, async (controller) => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...data, action }),
        ...(controller ? { signal: controller.signal } : {}),
      });
      let json;
      try {
        json = await response.json();
      } catch {
        throw new Error("服务暂时不可用，请稍后重试");
      }
      return { response, json };
    });
    result = outcome.json;
    if (!outcome.response.ok) {
      const error = new Error(result.error || "请求失败");
      error.status = outcome.response.status;
      throw error;
    }
    return result;
  } catch (error) {
    if (error && (error.name === "AbortError" || error.name === "TimeoutError")) {
      throw new Error(timeoutMessage(action));
    }
    if (error instanceof TypeError) {
      throw new Error(NETWORK_MESSAGE);
    }
    throw error;
  }
}
export const el = (id) => document.getElementById(id);
export const date = (value) =>
  new Date(value).toLocaleString("zh-CN", { hour12: false });
export function node(tag, text, className) {
  const result = document.createElement(tag);
  if (text !== undefined) result.textContent = text;
  if (className) result.className = className;
  return result;
}
export function details(ticket, target, admin = false) {
  target.replaceChildren();
  const heading = node("div", undefined, "split");
  heading.append(
    node("h2", ticket.title),
    node("span", ticket.status, "badge"),
  );
  target.append(
    heading,
    node("p", `${ticket.id} · ${date(ticket.createdAt)}`, "muted"),
  );
  for (const [label, value] of [
    ["反馈类型", ticket.category],
    ["使用场景", ticket.scenario],
    ["平台 / 版本", `${ticket.platform} / ${ticket.version || "未填写"}`],
    ["具体问题", ticket.problem],
    ["复现步骤", ticket.steps],
    ["期望结果", ticket.expected],
    ...(admin
      ? [
          ["用户 ID", ticket.userId],
          ["联系方式", `${ticket.contactType}：${ticket.contact}`],
          ["优先级", ticket.priority],
          ["负责人", ticket.assignee || "未分配"],
          ["归档", ticket.archived ? "已归档" : "未归档"],
        ]
      : []),
  ]) {
    if (!value) continue;
    const section = node("section", undefined, "section");
    section.append(node("h3", label), node("p", value));
    target.append(section);
  }
  const timeline = node(
    "div",
    undefined,
    admin ? "timeline admin-history" : "timeline",
  );
  const labels = {
    reply: "公开回复",
    note: "内部备注",
    status: "修改状态",
    priority: "设置优先级",
    category: "修改分类",
    assign: "分配负责人",
    archive: "归档操作",
  };
  for (const event of ticket.history) {
    const item = node(
      "article",
      undefined,
      event.action === "note" ? "internal" : "",
    );
    item.append(
      node("div", labels[event.action], "history-label"),
      node("small", date(event.at)),
      node(
        "p",
        event.action === "archive"
          ? event.value === "true"
            ? "已归档"
            : "已恢复"
          : event.value,
      ),
    );
    timeline.append(item);
  }
  const section = node("section", undefined, "section");
  section.append(
    node("h3", admin ? "操作记录" : "处理记录"),
    ticket.history.length
      ? timeline
      : node("p", "工单已提交，状态为待处理。", "muted"),
  );
  target.append(section);
}
