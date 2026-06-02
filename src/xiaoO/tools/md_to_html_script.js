/* ── 滚动进度条 ── */
  window.addEventListener("scroll", () => {
    const el  = document.documentElement;
    const pct = el.scrollTop / (el.scrollHeight - el.clientHeight) * 100;
    document.getElementById("progress").style.width = Math.min(pct, 100) + "%";
  });

  /* ── TOC 高亮当前章节 ── */
  (function () {
    const headings = Array.from(document.querySelectorAll("article h1,article h2,article h3"));
    const links    = Array.from(document.querySelectorAll(".toc a"));
    if (!links.length) return;
    const obs = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        links.forEach(l => l.classList.remove("active"));
        const a = links.find(l => l.getAttribute("href") === "#" + e.target.id);
        if (a) a.classList.add("active");
      });
    }, { rootMargin: "-10% 0px -80% 0px" });
    headings.forEach(h => obs.observe(h));
  })();

  /* ── h2 章节序号自动计数 ── */
  (function () {
    let idx = 0;
    document.querySelectorAll("article h2").forEach(el => {
      idx++;
      el.setAttribute("data-index", String(idx).padStart(2, "0"));
    });
  })();

  /* ── 代码块一键复制 ── */
  function copyCode(btn) {
    const code = btn.closest(".code-block").querySelector("code").innerText;
    navigator.clipboard.writeText(code).then(() => {
      btn.classList.add("copied");
      btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>';
      setTimeout(() => {
        btn.classList.remove("copied");
        btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
      }, 2000);
    });
  }

  /* ── 目录树收缩/展开 ── */
  function toggleToc(btn) {
    const expanded = btn.getAttribute("aria-expanded") === "true";
    btn.setAttribute("aria-expanded", String(!expanded));
    const parentItem = btn.closest(".toc-item");
    let nextEl = parentItem.nextElementSibling;
    if (nextEl && nextEl.classList.contains("toc-group")) {
      if (expanded) {
        nextEl.style.maxHeight = nextEl.scrollHeight + "px";
        void nextEl.offsetHeight;
        nextEl.classList.add("collapsed");
      } else {
        nextEl.classList.remove("collapsed");
        nextEl.style.maxHeight = nextEl.scrollHeight + "px";
        setTimeout(() => {
          if (!nextEl.classList.contains("collapsed")) {
            nextEl.style.maxHeight = "none";
          }
        }, 300);
      }
    }
  }
