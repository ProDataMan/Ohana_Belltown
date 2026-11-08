(async () => {
  const el = document.getElementById('edit-menu-link');
  if (!el) return;
  try {
    const session = await (window.ohanaSession || fetch('/api/session').then((r) => (r.ok ? r.json() : {})).catch(() => ({})));
    if (session.staff) {
      el.hidden = false;
    }
  } catch {
    // stay hidden
  }
})();
