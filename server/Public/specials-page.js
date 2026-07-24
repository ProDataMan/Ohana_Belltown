function escapeHtmlSpecialsPage(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadSpecialsPage() {
  const container = document.getElementById('specials-list');
  const emptyMessage = document.getElementById('no-specials-message');
  if (!container) return;

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
      emptyMessage.hidden = false;
      return;
    }

    container.innerHTML = featured
      .map((item) => {
        const image = (item.images || [])[0];
        const priceMarkup = item.price != null ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
        return `
          <article class="item">
            ${image ? `<img class="item-photo" src="${escapeHtmlSpecialsPage(image)}" alt="${escapeHtmlSpecialsPage(item.name)}" loading="lazy" />` : ''}
            <div class="item-body">
              <h3>${escapeHtmlSpecialsPage(item.name)}</h3>
              ${item.description ? `<p>${escapeHtmlSpecialsPage(item.description)}</p>` : ''}
            </div>
            ${priceMarkup}
          </article>
        `;
      })
      .join('');
  } catch {
    emptyMessage.hidden = false;
  }
}

loadSpecialsPage();
