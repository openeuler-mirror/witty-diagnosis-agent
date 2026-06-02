window.addEventListener("scroll", () => {
  const el = document.documentElement;
  const total = el.scrollHeight - el.clientHeight;
  const pct = total > 0 ? (el.scrollTop / total) * 100 : 0;
  document.getElementById("progress").style.width = Math.min(pct, 100) + "%";
});

(function () {
  const headings = Array.from(document.querySelectorAll("article h1, article h2, article h3"));
  const links = Array.from(document.querySelectorAll(".toc a"));
  if (!links.length) return;
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      links.forEach((link) => link.classList.remove("active"));
      const link = links.find((item) => item.getAttribute("href") === "#" + entry.target.id);
      if (link) link.classList.add("active");
    });
  }, { rootMargin: "-10% 0px -80% 0px" });
  headings.forEach((heading) => observer.observe(heading));
})();

(function () {
  let index = 0;
  document.querySelectorAll("article h2").forEach((heading) => {
    index += 1;
    heading.setAttribute("data-index", String(index).padStart(2, "0"));
  });
})();

function copyCode(button) {
  const code = button.closest(".code-block").querySelector("code").innerText;
  navigator.clipboard.writeText(code).then(() => {
    button.classList.add("copied");
    button.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    setTimeout(() => {
      button.classList.remove("copied");
      button.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
    }, 2000);
  });
}
