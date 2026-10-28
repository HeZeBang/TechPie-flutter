import { api, el, details } from "./common.js";
let receipt;
function tab(mode) {
  for (const name of ["new", "lookup"]) {
    el(`${name}-panel`).hidden = name !== mode;
    el(`${name}-tab`).setAttribute("aria-selected", String(name === mode));
  }
}
el("new-tab").onclick = () => tab("new");
el("lookup-tab").onclick = () => tab("lookup");
document.querySelector(".tabs").onkeydown = (event) => {
  if (["ArrowLeft", "ArrowRight"].includes(event.key)) {
    event.preventDefault();
    const mode = el("new-panel").hidden ? "new" : "lookup";
    tab(mode);
    el(`${mode}-tab`).focus();
  }
};
const form = el("feedback-form");
el("another-feedback").onclick = () => {
  receipt = null;
  form.reset();
  form.hidden = false;
  el("receipt").hidden = true;
  form.elements.contact.type = "email";
  form.elements.contact.autocomplete = "email";
  el("receipt-id").textContent = "";
  form.elements.userId.focus();
};
form.elements.contactType.onchange = () => {
  form.elements.contact.type =
    form.elements.contactType.value === "邮箱" ? "email" : "text";
  form.elements.contact.autocomplete =
    form.elements.contactType.value === "邮箱" ? "email" : "off";
};
form.onsubmit = async (event) => {
  event.preventDefault();
  const button = form.querySelector("button");
  button.disabled = true;
  el("form-message").textContent = "";
  try {
    receipt = await api("create", {
      ...Object.fromEntries(new FormData(form)),
      consent: form.elements.consent.checked,
    });
    el("receipt-id").textContent = receipt.id;
    form.hidden = true;
    el("receipt").hidden = false;
    el("receipt").focus();
  } catch (error) {
    el("form-message").textContent = error.message;
  } finally {
    button.disabled = false;
  }
};
el("save-receipt").onclick = () => {
  const file = new Blob(
    [
      `TechPie 工单凭证\n工单 ID：${receipt.id}\n查询入口：${location.origin}/\n请妥善保存工单 ID。\n`,
    ],
    { type: "text/plain;charset=utf-8" },
  );
  const url = URL.createObjectURL(file);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${receipt.id}.txt`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
el("view-receipt").onclick = () => {
  el("lookup-form").elements.id.value = receipt.id;
  tab("lookup");
  el("lookup-form").requestSubmit();
};
el("lookup-form").onsubmit = async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector("button");
  button.disabled = true;
  el("lookup-message").textContent = "";
  el("lookup-result").replaceChildren();
  try {
    const { ticket } = await api("lookup", {
      ...Object.fromEntries(new FormData(form)),
      id: form.elements.id.value.trim().toUpperCase(),
    });
    details(ticket, el("lookup-result"));
  } catch (error) {
    el("lookup-message").textContent = error.message;
  } finally {
    button.disabled = false;
  }
};
