/* Help page: highlights the topic you're reading in the table of contents. */
(() => {
  'use strict';
  const links = new Map(
    Array.from(document.querySelectorAll('.toc a[href^="#"]')).map((link) => [link.hash.slice(1), link])
  );
  const topics = Array.from(links.keys()).map((id) => document.getElementById(id)).filter(Boolean);
  if (!topics.length || !('IntersectionObserver' in window)) return;

  const visible = new Set();
  const mark = () => {
    const current = topics.find((topic) => visible.has(topic.id));
    for (const [id, link] of links) {
      if (current && id === current.id) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    }
  };

  // A topic counts as "being read" while it crosses a band near the top of the window.
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) visible.add(entry.target.id);
      else visible.delete(entry.target.id);
    }
    mark();
  }, { rootMargin: '-80px 0px -60% 0px' });
  topics.forEach((topic) => observer.observe(topic));
})();
