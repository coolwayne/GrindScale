import { bootstrap } from "./app";

bootstrap().catch((err) => {
  const root = document.getElementById("app");
  if (root) {
    root.innerHTML = `<div class="page"><p class="banner warn">啟動失敗：${String(err)}</p></div>`;
  }
  console.error(err);
});
