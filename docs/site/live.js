(function () {
  const t = window.MR_T;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(pointer: fine)").matches;
  const TAU = Math.PI * 2;
  const COLORS = {
    blue: "#0a84ff",
    green: "#34c759",
    orange: "#ff9f0a",
    yellow: "#ffd60a",
    purple: "#bf5af2",
    red: "#ff453a",
    track: "rgba(255,255,255,0.08)"
  };
  const ROTATE_MS = 2600;

  function onVisible(el, callback, threshold) {
    if (!el) return;
    if (!("IntersectionObserver" in window)) {
      callback();
      return;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        callback();
        observer.unobserve(entry.target);
      });
    }, { threshold: threshold || 0.4 });
    observer.observe(el);
  }

  function setupRotator() {
    const box = document.getElementById("rotator");
    let index = 0;
    let timer = null;
    const show = (text, animate) => {
      const next = document.createElement("span");
      next.className = "word";
      next.textContent = text;
      const old = [...box.querySelectorAll(".word")];
      box.appendChild(next);
      box.style.width = `${next.offsetWidth}px`;
      if (!animate) {
        old.forEach((el) => el.remove());
        return;
      }
      next.classList.add("enter");
      requestAnimationFrame(() => requestAnimationFrame(() => next.classList.remove("enter")));
      old.forEach((el) => {
        el.classList.add("leave");
        setTimeout(() => el.remove(), 600);
      });
    };
    const restart = () => {
      clearInterval(timer);
      index = 0;
      show(t("hero.words")[0], false);
      if (reduceMotion) return;
      timer = setInterval(() => {
        const words = t("hero.words");
        index = (index + 1) % words.length;
        show(words[index], true);
      }, ROTATE_MS);
    };
    document.addEventListener("mr:lang", restart);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(restart);
    restart();
  }

  function setupMarquee() {
    const track = document.getElementById("marquee");
    const build = () => {
      const items = t("marquee");
      track.innerHTML = "";
      for (let copy = 0; copy < 2; copy++) {
        items.forEach((item) => {
          const el = document.createElement("span");
          el.textContent = item;
          track.appendChild(el);
        });
      }
    };
    document.addEventListener("mr:lang", build);
    build();
  }

  function setupChips() {
    const stage = document.querySelector(".hero-stage");
    const chips = [...document.querySelectorAll(".chip-float")];
    const state = { cpu: 23, temp: 47.6, power: 13.2, net: 1.6 };
    const limits = { cpu: [4, 96, 9], temp: [38, 82, 1.6], power: [3, 38, 2.2], net: [0.1, 24, 1.4] };
    const format = {
      cpu: (v) => `${Math.round(v)}%`,
      temp: (v) => `${v.toFixed(1)}°C`,
      power: (v) => `${v.toFixed(1)} W`,
      net: (v) => `${v.toFixed(1)} MB/s`
    };
    const tick = () => {
      Object.keys(state).forEach((key) => {
        const [lo, hi, step] = limits[key];
        state[key] = Math.min(hi, Math.max(lo, state[key] + (Math.random() - 0.5) * 2 * step));
        const el = document.querySelector(`[data-live="${key}"]`);
        if (!el) return;
        el.textContent = format[key](state[key]);
        el.classList.remove("bump");
        void el.offsetWidth;
        el.classList.add("bump");
      });
    };
    if (!reduceMotion) setInterval(tick, 1400);
    if (!finePointer || reduceMotion) return;
    stage.addEventListener("pointermove", (e) => {
      const r = stage.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      chips.forEach((chip) => {
        const d = Number(chip.dataset.depth);
        chip.style.setProperty("--px", `${(x * d).toFixed(1)}px`);
        chip.style.setProperty("--py", `${(y * d).toFixed(1)}px`);
      });
    });
    stage.addEventListener("pointerleave", () => {
      chips.forEach((chip) => {
        chip.style.setProperty("--px", "0px");
        chip.style.setProperty("--py", "0px");
      });
    });
  }

  function setupCursorGlow() {
    const glow = document.getElementById("cursor-glow");
    if (!finePointer || reduceMotion) {
      glow.remove();
      return;
    }
    let tx = window.innerWidth / 2;
    let ty = window.innerHeight / 3;
    let x = tx;
    let y = ty;
    window.addEventListener("pointermove", (e) => {
      tx = e.clientX;
      ty = e.clientY;
      glow.classList.add("on");
    }, { passive: true });
    document.addEventListener("pointerleave", () => glow.classList.remove("on"));
    const loop = () => {
      x += (tx - x) * 0.12;
      y += (ty - y) * 0.12;
      glow.style.transform = `translate(${x}px, ${y}px)`;
      requestAnimationFrame(loop);
    };
    loop();
  }

  function fitCanvas(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  function roundBar(ctx, x, y, w, h, color) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, Math.min(w, h) / 2);
    ctx.fill();
  }

  function noise(seed, time) {
    return 0.5 + 0.25 * Math.sin(time * 1.3 + seed * 2.1) + 0.25 * Math.sin(time * 0.7 + seed * 5.3);
  }

  const VIZ = {
    spark(ctx, w, h, time) {
      const points = 48;
      const ys = [];
      for (let i = 0; i <= points; i++) {
        const s = i / points * 6 + time * 1.2;
        ys.push(h - 6 - (h - 14) * (0.3 + 0.35 * Math.sin(s) * Math.sin(s * 0.37 + 1) + 0.2 * Math.sin(s * 2.3)));
      }
      const grad = ctx.createLinearGradient(0, 0, 0, h);
      grad.addColorStop(0, "rgba(10,132,255,0.45)");
      grad.addColorStop(1, "rgba(10,132,255,0)");
      ctx.beginPath();
      ys.forEach((y, i) => (i ? ctx.lineTo((i / points) * w, y) : ctx.moveTo(0, y)));
      ctx.lineTo(w, h);
      ctx.lineTo(0, h);
      ctx.fillStyle = grad;
      ctx.fill();
      ctx.beginPath();
      ys.forEach((y, i) => (i ? ctx.lineTo((i / points) * w, y) : ctx.moveTo(0, y)));
      ctx.strokeStyle = COLORS.blue;
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.fillStyle = "#fff";
      ctx.beginPath();
      ctx.arc(w - 3, ys[points], 3.5, 0, TAU);
      ctx.fill();
    },
    ring(ctx, w, h, time) {
      const cx = h / 2 + 4;
      const cy = h / 2;
      const r = h / 2 - 7;
      const parts = [
        [0.3 + 0.05 * Math.sin(time), COLORS.blue],
        [0.22 + 0.04 * Math.sin(time * 1.3 + 1), COLORS.orange],
        [0.28 + 0.05 * Math.sin(time * 0.8 + 2), COLORS.purple]
      ];
      ctx.lineWidth = 9;
      ctx.strokeStyle = COLORS.track;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, TAU);
      ctx.stroke();
      let a = -Math.PI / 2 + time * 0.25;
      ctx.lineCap = "round";
      parts.forEach(([v, color]) => {
        ctx.strokeStyle = color;
        ctx.beginPath();
        ctx.arc(cx, cy, r, a + 0.08, a + v * TAU - 0.08);
        ctx.stroke();
        a += v * TAU;
      });
      const labels = [["App", COLORS.blue], ["Wired", COLORS.orange], ["Comp.", COLORS.purple]];
      ctx.font = "600 12px 'Plus Jakarta Sans', sans-serif";
      labels.forEach(([label, color], i) => {
        const y = 16 + i * 18;
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(h + 18, y - 4, 4, 0, TAU);
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,0.7)";
        ctx.fillText(label, h + 28, y);
        roundBar(ctx, h + 76, y - 7, Math.max(6, (w - h - 90) * parts[i][0] * 2.2), 6, color);
      });
    },
    cores(ctx, w, h, time) {
      const count = 12;
      const gap = 5;
      const bw = (w - gap * (count - 1)) / count;
      for (let i = 0; i < count; i++) {
        const v = noise(i, time * (i < 4 ? 2.2 : 1.4));
        const x = i * (bw + gap);
        roundBar(ctx, x, 4, bw, h - 8, COLORS.track);
        const bh = Math.max(bw, (h - 8) * v);
        roundBar(ctx, x, h - 4 - bh, bw, bh, i < 4 ? COLORS.blue : COLORS.green);
      }
    },
    temp(ctx, w, h, time) {
      const rows = [["SoC", 0.55, 0], ["Battery", 0.38, 2], ["SSD", 0.42, 4]];
      ctx.font = "600 12px 'Plus Jakarta Sans', sans-serif";
      rows.forEach(([label, base, seed], i) => {
        const y = 10 + i * 20;
        const v = Math.min(0.98, base + 0.25 * (noise(seed, time * 0.9) - 0.5) * 2);
        ctx.fillStyle = "rgba(255,255,255,0.7)";
        ctx.fillText(label, 0, y + 8);
        const x0 = 64;
        const bw = w - x0 - 56;
        roundBar(ctx, x0, y, bw, 8, COLORS.track);
        const grad = ctx.createLinearGradient(x0, 0, x0 + bw, 0);
        grad.addColorStop(0, COLORS.green);
        grad.addColorStop(0.6, COLORS.yellow);
        grad.addColorStop(1, COLORS.red);
        roundBar(ctx, x0, y, Math.max(8, bw * v), 8, grad);
        ctx.fillStyle = "#fff";
        ctx.fillText(`${(30 + v * 60).toFixed(1)}°`, w - 46, y + 8);
      });
    },
    power(ctx, w, h, time) {
      const count = 28;
      const gap = 3;
      const bw = (w - gap * (count - 1)) / count;
      for (let i = 0; i < count; i++) {
        const s = i * 0.45 + time * 1.6;
        const v = 0.25 + 0.55 * Math.abs(Math.sin(s * 0.6) * Math.cos(s * 0.23 + 1)) + 0.15 * Math.sin(s * 2.1);
        const bh = Math.max(4, (h - 6) * Math.min(1, Math.max(0.08, v)));
        const grad = ctx.createLinearGradient(0, h - bh, 0, h);
        grad.addColorStop(0, COLORS.yellow);
        grad.addColorStop(1, "rgba(255,159,10,0.35)");
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.roundRect(i * (bw + gap), h - bh, bw, bh, [3, 3, 1, 1]);
        ctx.fill();
      }
    },
    update(ctx, w, h, time) {
      const cycle = (time * 0.35) % 1;
      const p = Math.min(1, cycle / 0.7);
      const done = cycle >= 0.7;
      const cx = h / 2;
      const cy = h / 2;
      const r = h / 2 - 8;
      ctx.lineWidth = 5;
      ctx.lineCap = "round";
      ctx.strokeStyle = COLORS.track;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, TAU);
      ctx.stroke();
      ctx.strokeStyle = done ? COLORS.green : COLORS.blue;
      ctx.beginPath();
      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + p * TAU);
      ctx.stroke();
      if (done) {
        ctx.strokeStyle = COLORS.green;
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(cx - r * 0.4, cy);
        ctx.lineTo(cx - r * 0.08, cy + r * 0.32);
        ctx.lineTo(cx + r * 0.45, cy - r * 0.3);
        ctx.stroke();
      }
      ctx.font = "700 14px 'JetBrains Mono', monospace";
      ctx.fillStyle = "rgba(255,255,255,0.55)";
      ctx.fillText("v1.9.2", h + 12, cy - 4);
      ctx.fillStyle = done ? COLORS.green : "#fff";
      ctx.fillText(done ? "→ v1.9.3 ✓" : `→ ${Math.round(p * 100)}%`, h + 12, cy + 16);
    }
  };

  function setupViz() {
    const canvases = [...document.querySelectorAll("canvas.viz")];
    const visible = new Set();
    if ("IntersectionObserver" in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach((e) => (e.isIntersecting ? visible.add(e.target) : visible.delete(e.target)));
      });
      canvases.forEach((c) => observer.observe(c));
    } else {
      canvases.forEach((c) => visible.add(c));
    }
    const start = performance.now();
    const draw = (now) => {
      const time = reduceMotion ? 2 : (now - start) / 1000;
      canvases.forEach((canvas) => {
        if (!visible.has(canvas) && !reduceMotion) return;
        const { ctx, w, h } = fitCanvas(canvas);
        ctx.clearRect(0, 0, w, h);
        const card = canvas.closest(".card");
        const boost = card && card.matches(":hover") ? 1.8 : 1;
        VIZ[canvas.dataset.viz](ctx, w, h, time * boost);
      });
      if (!reduceMotion) requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  function setupScore() {
    const card = document.getElementById("score-card");
    const fill = document.getElementById("score-fill");
    const num = document.getElementById("score-num");
    const target = 70;
    const circumference = 2 * Math.PI * 34;
    fill.style.strokeDasharray = `${circumference}`;
    fill.style.strokeDashoffset = `${circumference}`;
    onVisible(card, () => {
      card.classList.add("in");
      fill.style.strokeDashoffset = `${circumference * (1 - target / 100)}`;
      const begin = performance.now();
      const step = (now) => {
        const p = Math.min(1, (now - begin) / 1400);
        num.textContent = Math.round(target * (1 - Math.pow(1 - p, 3)));
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }, 0.5);
  }

  function setupTyping() {
    const code = document.getElementById("xattr-cmd");
    const text = document.getElementById("xattr-text");
    const full = code.dataset.full;
    if (reduceMotion) return;
    text.textContent = "";
    onVisible(code, () => {
      let i = 0;
      const timer = setInterval(() => {
        i += 1;
        text.textContent = full.slice(0, i);
        if (i >= full.length) {
          clearInterval(timer);
          code.classList.add("typed");
        }
      }, 28);
    }, 0.8);
  }

  setupRotator();
  setupMarquee();
  setupChips();
  setupCursorGlow();
  setupViz();
  setupScore();
  setupTyping();
})();
