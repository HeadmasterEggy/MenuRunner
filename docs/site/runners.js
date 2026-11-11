(function () {
  const TAU = Math.PI * 2;
  const SPEEDS = [0.6, 1.5, 3.2];

  function drawFan(ctx, w, h, phase, level, color) {
    const r = Math.min(w, h) / 2 - 1.5;
    const cx = w / 2;
    const cy = h / 2;
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(1.4, r * 0.12);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, TAU);
    ctx.stroke();
    const trail = [1, 3, 5][level];
    for (let k = trail; k >= 0; k--) {
      ctx.globalAlpha = k === 0 ? 1 : 0.18 / k;
      ctx.fillStyle = color;
      const angle = phase * 2.2 - k * 0.12;
      for (let b = 0; b < 4; b++) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(angle + (b * TAU) / 4);
        ctx.beginPath();
        ctx.ellipse(r * 0.42, r * 0.12, r * 0.42, r * 0.2, 0.5, 0, TAU);
        ctx.fill();
        ctx.restore();
      }
    }
    ctx.globalAlpha = 1;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.14, 0, TAU);
    ctx.fill();
  }

  function heartbeatY(x, beats, amp) {
    const period = 1 / beats;
    const p = ((x % period) + period) % period / period;
    if (p < 0.38) return 0;
    if (p < 0.43) return amp * 0.15 * Math.sin(((p - 0.38) / 0.05) * Math.PI);
    if (p < 0.47) return -amp * 0.25 * ((p - 0.43) / 0.04);
    if (p < 0.52) return -amp * 0.25 + amp * 1.25 * ((p - 0.47) / 0.05);
    if (p < 0.57) return amp - amp * 1.45 * ((p - 0.52) / 0.05);
    if (p < 0.6) return -amp * 0.45 + amp * 0.45 * ((p - 0.57) / 0.03);
    if (p < 0.75) return amp * 0.22 * Math.sin(((p - 0.6) / 0.15) * Math.PI);
    return 0;
  }

  function drawHeart(ctx, w, h, phase, level, color) {
    const beats = [1, 1.6, 2.4][level];
    const amp = h * [0.3, 0.38, 0.44][level];
    const mid = h * 0.58;
    const steps = Math.ceil(w);
    let lastX = 0;
    let lastY = mid;
    ctx.lineWidth = Math.max(1.3, h * 0.08);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (let i = 0; i <= steps; i++) {
      const x = (i / steps) * w;
      const y = mid - heartbeatY(i / steps + phase * 0.35, beats, amp);
      ctx.globalAlpha = Math.pow(i / steps, 1.6);
      ctx.strokeStyle = color;
      ctx.beginPath();
      ctx.moveTo(lastX, lastY);
      ctx.lineTo(x, y);
      ctx.stroke();
      lastX = x;
      lastY = y;
    }
    ctx.globalAlpha = 1;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(lastX - 1.5, lastY, Math.max(1.6, h * 0.08), 0, TAU);
    ctx.fill();
  }

  function drawBars(ctx, w, h, phase, level, color) {
    const count = 5;
    const gap = w / (count * 2.2);
    const bw = gap * 1.2;
    const total = count * bw + (count - 1) * gap;
    const x0 = (w - total) / 2;
    const maxH = h * [0.45, 0.72, 0.95][level];
    ctx.fillStyle = color;
    for (let i = 0; i < count; i++) {
      const v = 0.5 + 0.5 * Math.sin(phase * 3 + i * 1.3) * Math.cos(phase * 1.7 + i * 0.7);
      const bh = Math.max(bw, maxH * (0.25 + 0.75 * v));
      const x = x0 + i * (bw + gap);
      const y = (h - bh) / 2;
      ctx.beginPath();
      ctx.roundRect(x, y, bw, bh, bw / 2);
      ctx.fill();
    }
  }

  function drawBall(ctx, w, h, phase, level, color) {
    const r = h * 0.15;
    const ground = h - 2;
    const height = (h - r * 2 - 4) * [0.45, 0.75, 1][level];
    const p = (phase * 0.9) % 1;
    const lift = 4 * p * (1 - p);
    const squash = lift < 0.12 ? 1 + (0.12 - lift) * 3 : 1;
    const cy = ground - r - lift * height;
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.25 * (1 - lift * 0.7);
    ctx.beginPath();
    ctx.ellipse(w / 2, ground, r * (1.1 - lift * 0.4), r * 0.25, 0, 0, TAU);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.beginPath();
    ctx.ellipse(w / 2, cy + (squash - 1) * r * 0.5, r * squash, r / squash, 0, 0, TAU);
    ctx.fill();
  }

  function drawRadar(ctx, w, h, phase, level, color) {
    const r = Math.min(w, h) / 2 - 1.5;
    const cx = w / 2;
    const cy = h / 2;
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(1.4, r * 0.12);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, TAU);
    ctx.stroke();
    ctx.globalAlpha = 0.35;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.5, 0, TAU);
    ctx.moveTo(cx - r, cy);
    ctx.lineTo(cx + r, cy);
    ctx.moveTo(cx, cy - r);
    ctx.lineTo(cx, cy + r);
    ctx.stroke();
    const angle = phase * 1.6 - Math.PI / 2;
    const trail = [0.5, 0.9, 1.4][level];
    const slices = 14;
    ctx.fillStyle = color;
    for (let i = 0; i < slices; i++) {
      ctx.globalAlpha = 0.35 * (1 - i / slices);
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, r * 0.92, angle - (trail * (i + 1)) / slices, angle - (trail * i) / slices);
      ctx.closePath();
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(1.4, r * 0.1);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(angle) * r * 0.92, cy + Math.sin(angle) * r * 0.92);
    ctx.stroke();
    const blips = [[0.5, 0.6], [2.4, 0.4], [4.1, 0.75], [5.3, 0.3]].slice(0, level + 2);
    for (const [a, d] of blips) {
      ctx.beginPath();
      ctx.arc(cx + Math.cos(a) * r * d, cy + Math.sin(a) * r * d, Math.max(1.2, r * 0.09), 0, TAU);
      ctx.fill();
    }
  }

  function drawClock(ctx, w, h, phase, level, color) {
    const r = Math.min(w, h) / 2 - 1.5;
    const cx = w / 2;
    const cy = h / 2;
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = Math.max(1.4, r * 0.12);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, TAU);
    ctx.stroke();
    ctx.lineWidth = Math.max(1, r * 0.06);
    for (let i = 0; i < 12; i++) {
      const a = (i * TAU) / 12;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(a) * r * 0.78, cy + Math.sin(a) * r * 0.78);
      ctx.lineTo(cx + Math.cos(a) * r * 0.88, cy + Math.sin(a) * r * 0.88);
      ctx.stroke();
    }
    const blur = [1, 3, 6][level];
    const minute = phase * 1.4 - Math.PI / 2;
    const hour = phase * 0.12 - Math.PI / 2;
    ctx.lineCap = "round";
    for (let k = blur - 1; k >= 0; k--) {
      ctx.globalAlpha = k === 0 ? 1 : 0.22 / k;
      ctx.lineWidth = Math.max(1.4, r * 0.11);
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      const a = minute - k * 0.1;
      ctx.lineTo(cx + Math.cos(a) * r * 0.7, cy + Math.sin(a) * r * 0.7);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.lineWidth = Math.max(1.6, r * 0.14);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(hour) * r * 0.45, cy + Math.sin(hour) * r * 0.45);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.1, 0, TAU);
    ctx.fill();
  }

  window.MR_RUNNERS = {
    speeds: SPEEDS,
    list: [
      { id: "fan", draw: drawFan, aspect: 1 },
      { id: "heart", draw: drawHeart, aspect: 2 },
      { id: "bars", draw: drawBars, aspect: 1.4 },
      { id: "ball", draw: drawBall, aspect: 1 },
      { id: "radar", draw: drawRadar, aspect: 1 },
      { id: "clock", draw: drawClock, aspect: 1 }
    ]
  };
})();
