/* Section entrances on the home page: each part rises in once, the first time its section scrolls
   into view. Without JavaScript, or with Reduce Motion, everything is simply there. */
(() => {
  'use strict';

  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const groups = document.querySelectorAll('[data-reveal-group]');
  document.documentElement.classList.add('reveal');

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -12% 0px' });

  for (const group of groups) observer.observe(group);

  /* Printing shows everything, scrolled to or not. */
  addEventListener('beforeprint', () => {
    for (const group of groups) group.classList.add('is-in');
  });
})();
