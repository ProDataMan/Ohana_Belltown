function escapeHtmlSpecials(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// Same session-persisted table id used on the menu pages — set once a
// table's QR code has been scanned, so prices stay hidden until then.
function getTableId() {
  const fromQuery = new URLSearchParams(window.location.search).get('table');
  if (fromQuery) {
    sessionStorage.setItem('ohana_table_id', fromQuery);
    return fromQuery;
  }
  return sessionStorage.getItem('ohana_table_id');
}

async function loadSpecials() {
  const section = document.getElementById('specials-section');
  const container = document.getElementById('specials-list');
  if (!section || !container) return;
  const tableId = getTableId();

  try {
    const response = await fetch('/api/menu');
    if (!response.ok) throw new Error('Unable to load specials.');
    const data = await response.json();

    const featured = [];
    (data.categories || []).forEach((category) => {
      (category.items || []).forEach((item) => {
        if (item.featured && item.available !== false) featured.push(item);
      });
    });

    if (!featured.length) {
      section.hidden = true;
      return;
    }

    section.hidden = false;
    container.innerHTML = featured
      .map((item) => {
        const image = (item.images || [])[0];
        const priceMarkup = item.price != null && tableId ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
        return `
          <article class="item">
            ${image ? `<img class="item-photo" src="${escapeHtmlSpecials(image)}" alt="${escapeHtmlSpecials(item.name)}" loading="lazy" />` : ''}
            <div class="item-body">
              <h3>${escapeHtmlSpecials(item.name)}</h3>
              ${item.description ? `<p>${escapeHtmlSpecials(item.description)}</p>` : ''}
            </div>
            ${priceMarkup}
          </article>
        `;
      })
      .join('');
  } catch {
    section.hidden = true;
  }
}

loadSpecials();
