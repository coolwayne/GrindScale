import type { HistogramBin } from "./types";

const X_MAX = 1000;

function appendCatmull(ctx: CanvasRenderingContext2D, pts: { x: number; y: number }[]): void {
  if (pts.length < 2) return;
  const ctrl: { x: number; y: number }[] = [];
  ctrl.push({
    x: pts[0].x + (pts[0].x - pts[1].x),
    y: pts[0].y + (pts[0].y - pts[1].y),
  });
  ctrl.push(...pts);
  const last = pts[pts.length - 1];
  const prev = pts[pts.length - 2];
  ctrl.push({
    x: last.x + (last.x - prev.x),
    y: last.y + (last.y - prev.y),
  });

  ctx.moveTo(pts[0].x, pts[0].y);
  for (let k = 0; k < pts.length - 1; k++) {
    const p0 = ctrl[k];
    const p1 = ctrl[k + 1];
    const p2 = ctrl[k + 2];
    const p3 = ctrl[k + 3];
    const t1x = (p2.x - p0.x) * 0.5;
    const t1y = (p2.y - p0.y) * 0.5;
    const t2x = (p3.x - p1.x) * 0.5;
    const t2y = (p3.y - p1.y) * 0.5;
    const c1x = p1.x + t1x / 3;
    const c1y = p1.y + t1y / 3;
    const c2x = p2.x - t2x / 3;
    const c2y = p2.y - t2y / 3;
    ctx.bezierCurveTo(c1x, c1y, c2x, c2y, p2.x, p2.y);
  }
}

export function drawHistogramChart(canvas: HTMLCanvasElement, bins: HistogramBin[]): void {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const w = Math.max(280, rect.width);
  const h = 220;
  canvas.width = Math.floor(w * dpr);
  canvas.height = Math.floor(h * dpr);
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;

  const ctx = canvas.getContext("2d");
  if (!ctx || bins.length === 0) return;
  ctx.scale(dpr, dpr);

  const padL = 8;
  const padR = 8;
  const padT = 12;
  const padB = 32;
  const bw = w - padL - padR;
  const bh = h - padT - padB;
  const baselineY = h - padB;

  const maxC = Math.max(1, ...bins.map((b) => b.count));
  const pts = bins.map((b) => {
    const centerUm = (b.start + b.end) / 2;
    const x = padL + (centerUm / X_MAX) * bw;
    const y = padT + bh * (1 - b.count / maxC);
    return { x, y };
  });

  ctx.fillStyle = "#F7F0E6";
  ctx.fillRect(0, 0, w, h);

  ctx.strokeStyle = "rgba(224,204,204,0.7)";
  ctx.beginPath();
  ctx.moveTo(padL, baselineY);
  ctx.lineTo(w - padR, baselineY);
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(pts[0].x, baselineY);
  ctx.lineTo(pts[0].x, pts[0].y);
  appendCatmull(ctx, pts);
  ctx.lineTo(pts[pts.length - 1].x, baselineY);
  ctx.closePath();
  ctx.fillStyle = "rgba(230,133,56,0.22)";
  ctx.fill();

  ctx.beginPath();
  ctx.moveTo(pts[0].x, pts[0].y);
  appendCatmull(ctx, pts);
  ctx.strokeStyle = "#B87A47";
  ctx.lineWidth = 2.5;
  ctx.lineCap = "round";
  ctx.stroke();

  ctx.fillStyle = "#000";
  ctx.font = "9px system-ui,sans-serif";
  ctx.textAlign = "center";
  for (const um of [0, 200, 400, 600, 800, 1000]) {
    const fx = padL + (um / X_MAX) * bw;
    ctx.fillText(String(um), fx, h - 6);
  }
}
