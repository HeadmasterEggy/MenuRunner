(function () {
  const strings = window.MR_STRINGS;
  const runners = window.MR_RUNNERS;
  const LANG_KEY = "menurunner-lang";
  const RELEASE_API = "https://api.github.com/repos/HeadmasterEggy/MenuRunner/releases/latest";
  const HERO_SIZE = 22;
  const PRESETS = [15, 50, 90];
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let lang = initialLang();
  let playLoad = 0.15;
  let heroLoad = 0.23;
  let heroTarget = 0.23;
  let heroIndex = 0;
  let hero = null;
  const sparkHistory = Array.from({ length: 24 }, () => 0.2);

  function initialLang() {
    try {
      const saved = localStorage.getItem(LANG_KEY);
      if (saved === "en" || saved === "zh") return saved;
    } catch (e) {}
    return (navigator.language || "en").toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  function t(key) {
    return (strings[lang] && strings[lang][key]) || strings.en[key] || key;
  }

  function applyLang() {
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    document.querySelectorAll("[data-i18n]").forEach((el) => {
      el.textContent = t(el.dataset.i18n);
    });
    document.querySelectorAll("img[data-src-en]").forEach((img) => {
      img.src = lang === "zh" ? img.dataset.srcZh : img.dataset.srcEn;
    });
    document.getElementById("lang-toggle").textContent = t("lang.switch");
    document.dispatchEvent(new CustomEvent("mr:lang", { detail: { lang, t } }));
    updateClock();
  }

  function setupLangToggle() {
    document.getElementById("lang-toggle").addEventListener("click", () => {
      lang = lang === "zh" ? "en" : "zh";
      try {
        localStorage.setItem(LANG_KEY, lang);
      } catch (e) {}
      document.body.classList.add("lang-swap");
      setTimeout(() => {
        applyLang();
        document.body.classList.remove("lang-swap");
      }, 160);
    });
  }

  function updateClock() {
    const now = new Date();
    const locale = lang === "zh" ? "zh-CN" : "en-US";
    const day = now.toLocaleDateString(locale, { weekday: "short" });
    const time = now.toLocaleTimeString(locale, { hour: "numeric", minute: "2-digit" });
    document.getElementById("hero-clock").textContent = `${day} ${time}`;
  }

  function fetchVersion() {
    fetch(RELEASE_API)
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((data) => {
        if (!data || !data.tag_name) return;
        document.getElementById("version").textContent = data.tag_name;
        const dmg = (data.assets || []).find((a) => a.name.endsWith(".dmg"));
        if (dmg) document.getElementById("download").href = dmg.browser_download_url;
      })
      .catch(() => {
        document.getElementById("version-line").hidden = true;
      });
  }

  function setupCopy() {
    const btn = document.getElementById("copy-btn");
    btn.addEventListener("click", () => {
      const text = document.getElementById("xattr-cmd").dataset.full;
      const done = () => {
        btn.textContent = t("install.copied");
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = t("install.copy");
          btn.classList.remove("copied");
        }, 1600);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, done);
    });
  }

  function prepareCanvas(canvas, w, h) {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }

  function levelFor(load) {
    if (load > 0.66) return 2;
    if (load > 0.33) return 1;
    return 0;
  }

  function setHeroRunner(index) {
    heroIndex = index;
    const runner = runners.list[index];
    const w = Math.round(HERO_SIZE * runner.aspect);
    hero = { runner, w, h: HERO_SIZE, ctx: prepareCanvas(document.getElementById("hero-canvas"), w, HERO_SIZE), phase: 0 };
    document.querySelectorAll("#hero-picker button").forEach((b, i) => b.classList.toggle("active", i === index));
    document.querySelectorAll(".runner-tile").forEach((tile, i) => tile.classList.toggle("selected", i === index));
    const chip = document.getElementById("hero-runner");
    chip.classList.remove("pop");
    void chip.offsetWidth;
    chip.classList.add("pop");
  }

  function setupHero() {
    const picker = document.getElementById("hero-picker");
    runners.list.forEach((runner, i) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.dataset.i18n = `runner.${runner.id}`;
      btn.textContent = t(`runner.${runner.id}`);
      btn.addEventListener("click", () => setHeroRunner(i));
      picker.appendChild(btn);
    });
    const panel = document.getElementById("hero-panel");
    const chip = document.getElementById("hero-runner");
    chip.addEventListener("click", () => {
      const closed = panel.classList.toggle("closed");
      chip.classList.toggle("open", !closed);
    });
    chip.classList.add("open");
    const stage = document.querySelector(".hero-stage");
    stage.addEventListener("pointerenter", () => (heroTarget = Math.max(heroTarget, 0.55)));
    setHeroRunner(0);
  }

  function setPlayLoad(percent) {
    playLoad = percent / 100;
    document.getElementById("load-slider").value = percent;
    document.getElementById("load-value").textContent = `${percent}%`;
    const level = levelFor(playLoad);
    document.querySelectorAll(".load-control button").forEach((b) => b.classList.toggle("active", Number(b.dataset.level) === level));
    document.getElementById("load-slider").style.setProperty("--fill", `${percent}%`);
    document.querySelector(".playground").dataset.level = level;
  }

  function buildPlayground() {
    const grid = document.getElementById("runner-grid");
    const tiles = runners.list.map((runner, i) => {
      const tile = document.createElement("button");
      tile.type = "button";
      tile.className = "runner-tile";
      const bar = document.createElement("div");
      bar.className = "mini-bar";
      const canvas = document.createElement("canvas");
      bar.appendChild(canvas);
      const label = document.createElement("span");
      label.dataset.i18n = `runner.${runner.id}`;
      label.textContent = t(`runner.${runner.id}`);
      tile.append(bar, label);
      tile.addEventListener("click", () => setHeroRunner(i));
      grid.appendChild(tile);
      const h = 40;
      const w = Math.round(h * runner.aspect);
      return { runner, ctx: prepareCanvas(canvas, w, h), w, h, phase: Math.random() * 10 };
    });
    document.querySelectorAll(".load-control button").forEach((btn) => {
      btn.addEventListener("click", () => setPlayLoad(PRESETS[Number(btn.dataset.level)]));
    });
    document.getElementById("load-slider").addEventListener("input", (e) => setPlayLoad(Number(e.target.value)));
    setPlayLoad(15);
    return tiles;
  }

  function sparkPath(ctx, w, h) {
    ctx.beginPath();
    sparkHistory.forEach((v, i) => {
      const x = (i / (sparkHistory.length - 1)) * w;
      const y = h - 1 - v * (h - 2);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
  }

  function drawSpark(ctx, w, h) {
    ctx.clearRect(0, 0, w, h);
    sparkPath(ctx, w, h);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fillStyle = "rgba(255,255,255,0.28)";
    ctx.fill();
    sparkPath(ctx, w, h);
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 1.2;
    ctx.stroke();
  }

  function isVisible(el) {
    const r = el.getBoundingClientRect();
    return r.bottom > 0 && r.top < window.innerHeight;
  }

  window.MR_T = t;
  window.MR_getLang = () => lang;

  function start() {
    applyLang();
    setupLangToggle();
    setupCopy();
    fetchVersion();
    setInterval(updateClock, 30000);

    const tiles = buildPlayground();
    setupHero();
    const sparkCtx = prepareCanvas(document.getElementById("hero-spark"), 34, 14);
    const cpuLabel = document.getElementById("hero-cpu");
    const stage = document.querySelector(".hero-stage");
    const playground = document.querySelector(".playground");
    let last = performance.now();
    let sampleTimer = 0;

    function frame(now) {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      sampleTimer += dt;
      if (sampleTimer > 1) {
        sampleTimer = 0;
        if (Math.random() < 0.2) heroTarget = Math.random() < 0.5 ? 0.08 + Math.random() * 0.2 : 0.4 + Math.random() * 0.55;
        sparkHistory.push(heroLoad);
        sparkHistory.shift();
        cpuLabel.textContent = `${Math.round(heroLoad * 100)}%`;
      }
      heroLoad += (heroTarget - heroLoad) * Math.min(1, dt * 1.5);

      if (isVisible(stage)) {
        const heroLevel = levelFor(heroLoad);
        hero.phase += dt * runners.speeds[heroLevel];
        hero.ctx.clearRect(0, 0, hero.w, hero.h);
        hero.runner.draw(hero.ctx, hero.w, hero.h, hero.phase, heroLevel, "#fff");
        drawSpark(sparkCtx, 34, 14);
      }

      if (isVisible(playground)) {
        const level = levelFor(playLoad);
        const speed = runners.speeds[level] * (0.85 + playLoad * 0.3);
        const ink = getComputedStyle(document.body).getPropertyValue("--runner-ink").trim() || "#fff";
        tiles.forEach((tile) => {
          tile.phase += dt * speed;
          tile.ctx.clearRect(0, 0, tile.w, tile.h);
          tile.runner.draw(tile.ctx, tile.w, tile.h, tile.phase, level, ink);
        });
      }
      if (!reduceMotion) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  start();
})();
