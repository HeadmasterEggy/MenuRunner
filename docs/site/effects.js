(function () {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(pointer: fine)").matches;

  function setupReveal() {
    const items = document.querySelectorAll(".reveal");
    if (reduceMotion || !("IntersectionObserver" in window)) {
      items.forEach((el) => el.classList.add("in"));
      return;
    }
    const groups = new Map();
    items.forEach((el) => {
      const parent = el.parentElement;
      const index = groups.get(parent) || 0;
      groups.set(parent, index + 1);
      el.style.setProperty("--delay", `${Math.min(index, 6) * 70}ms`);
    });
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.15, rootMargin: "0px 0px -40px 0px" }
    );
    items.forEach((el) => observer.observe(el));
  }

  function setupCounters() {
    const counters = document.querySelectorAll("[data-count]");
    const run = (el) => {
      const target = Number(el.dataset.count);
      const suffix = el.dataset.suffix || "";
      const duration = 1200;
      const begin = performance.now();
      const step = (now) => {
        const p = Math.min(1, (now - begin) / duration);
        const eased = 1 - Math.pow(1 - p, 3);
        el.textContent = `${Math.round(target * eased)}${suffix}`;
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    };
    if (reduceMotion || !("IntersectionObserver" in window)) {
      counters.forEach((el) => (el.textContent = `${el.dataset.count}${el.dataset.suffix || ""}`));
      return;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        run(entry.target);
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.6 });
    counters.forEach((el) => observer.observe(el));
  }

  function setupTilt() {
    if (reduceMotion || !finePointer) return;
    document.querySelectorAll("[data-tilt]").forEach((el) => {
      const max = Number(el.dataset.tilt) || 6;
      el.classList.add("tiltable");
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        el.style.setProperty("--rx", `${(-y * max).toFixed(2)}deg`);
        el.style.setProperty("--ry", `${(x * max).toFixed(2)}deg`);
        el.style.setProperty("--gx", `${((x + 0.5) * 100).toFixed(1)}%`);
        el.style.setProperty("--gy", `${((y + 0.5) * 100).toFixed(1)}%`);
      });
      el.addEventListener("pointerleave", () => {
        el.style.setProperty("--rx", "0deg");
        el.style.setProperty("--ry", "0deg");
      });
    });
  }

  function setupSpotlight() {
    if (!finePointer) return;
    document.querySelectorAll(".card, .steps li, .runner-tile").forEach((el) => {
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        el.style.setProperty("--mx", `${e.clientX - r.left}px`);
        el.style.setProperty("--my", `${e.clientY - r.top}px`);
      });
    });
  }

  function setupScroll() {
    const bar = document.getElementById("progress");
    const nav = document.querySelector(".nav");
    const layers = document.querySelectorAll("[data-parallax]");
    const links = [...document.querySelectorAll(".nav-links a")];
    const sections = links.map((a) => document.querySelector(a.getAttribute("href")));
    let ticking = false;
    const update = () => {
      ticking = false;
      const y = window.scrollY;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      bar.style.transform = `scaleX(${max > 0 ? y / max : 0})`;
      nav.classList.toggle("scrolled", y > 8);
      if (!reduceMotion) layers.forEach((el) => (el.style.transform = `translateY(${y * Number(el.dataset.parallax)}px)`));
      let current = -1;
      sections.forEach((s, i) => {
        if (s && s.getBoundingClientRect().top < window.innerHeight * 0.4) current = i;
      });
      links.forEach((a, i) => a.classList.toggle("current", i === current));
    };
    window.addEventListener("scroll", () => {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    }, { passive: true });
    update();
  }

  function setupMagnet() {
    if (reduceMotion || !finePointer) return;
    document.querySelectorAll(".btn.primary").forEach((btn) => {
      btn.addEventListener("pointermove", (e) => {
        const r = btn.getBoundingClientRect();
        const x = e.clientX - r.left - r.width / 2;
        const y = e.clientY - r.top - r.height / 2;
        btn.style.transform = `translate(${x * 0.15}px, ${y * 0.25}px)`;
      });
      btn.addEventListener("pointerleave", () => (btn.style.transform = ""));
    });
  }

  setupReveal();
  setupCounters();
  setupTilt();
  setupSpotlight();
  setupScroll();
  setupMagnet();
})();
