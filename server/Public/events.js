function escapeHtmlEventsPublic(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadPublicEvents() {
  const container = document.getElementById('events-list');
  if (!container) return;
  try {
    const response = await fetch('/api/events');
    if (!response.ok) throw new Error('Unable to load events.');
    const data = await response.json();
    const active = (data.events || []).filter((e) => e.active);
    if (!active.length) {
      container.innerHTML = '<p>Ask staff about what\'s on this week.</p>';
      return;
    }
    container.innerHTML = `
      <div class="items">
        ${active
          .map(
            (e) => `
          <article class="item">
            <div class="item-body">
              <h3>${escapeHtmlEventsPublic(e.title)}</h3>
              <p><strong>${escapeHtmlEventsPublic(e.schedule)}</strong></p>
              ${e.description ? `<p>${escapeHtmlEventsPublic(e.description)}</p>` : ''}
            </div>
          </article>
        `
          )
          .join('')}
      </div>
    `;
  } catch {
    container.innerHTML = '';
  }
}

loadPublicEvents();
