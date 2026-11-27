function escapeHtmlSpecialsPage(value) {
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

function renderItemCards(items) {
  const tableId = getTableId();
  return items
    .map((item) => {
      const image = (item.images || [])[0];
      const priceMarkup = item.price != null && tableId ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
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

    container.innerHTML = renderItemCards(featured);
  } catch {
    emptyMessage.hidden = false;
  }
}

async function loadPopularItems() {
  const container = document.getElementById('popular-items-list');
  const emptyMessage = document.getElementById('no-popular-message');
  if (!container) return;

  try {
    const response = await fetch('/api/analytics/popular-items?days=30&limit=6');
    if (!response.ok) throw new Error('Unable to load popular items.');
    const items = await response.json();
    if (!items.length) {
      emptyMessage.hidden = false;
      return;
    }
    container.innerHTML = renderItemCards(items);
  } catch {
    emptyMessage.hidden = false;
  }
}

/// The week's day-of-week deals (Musubi Monday, Taco Tuesday…), today's
/// highlighted. Edited on the staff Daily Specials page.
async function loadDailyDeals() {
  const section = document.getElementById('daily-deals-section');
  const list = document.getElementById('daily-deals-list');
  try {
    const response = await fetch('/api/daily-specials');
    if (!response.ok) return;
    const data = await response.json();
    if (!data.week.length) return;
    const days = ['', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const esc = (v) => String(v ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    list.innerHTML = data.week
      .map(
        (deal) => `
        <li class="${deal.weekday === data.todayWeekday ? 'today' : ''}">
          <span class="daily-deal-day">${days[deal.weekday]}${deal.weekday === data.todayWeekday ? ' &middot; today' : ''}</span>
          <a href="/deal/${encodeURIComponent(deal.id)}"><strong>${esc(deal.title)}</strong></a>: ${esc(deal.deal)}
          ${deal.details ? `<span class="hint">${esc(deal.details)}</span>` : ''}
        </li>
      `
      )
      .join('');
    section.hidden = false;
  } catch {}
}

loadDailyDeals();
loadSpecialsPage();
loadPopularItems();
