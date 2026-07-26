function escapeHtmlAnalytics(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderHbarTable(el, rows, { labelHeader, valueHeader, formatValue = (v) => v }) {
  if (!rows.length) {
    el.innerHTML = '<p class="hint">No data yet.</p>';
    return;
  }
  const maxValue = Math.max(...rows.map((r) => r.value));
  el.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>${labelHeader}</th><th>${valueHeader}</th><th></th></tr></thead>
        <tbody>
          ${rows
            .map(
              (r) => `
            <tr>
              <td>${escapeHtmlAnalytics(r.label)}</td>
              <td>${formatValue(r.value)}</td>
              <td style="width: 40%;">
                <div class="analytics-hbar" style="width: ${Math.max(4, Math.round((r.value / maxValue) * 100))}%"></div>
              </td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

async function loadAnalytics() {
  const overviewEl = document.getElementById('overview');
  const chartEl = document.getElementById('daily-chart');
  const topPagesEl = document.getElementById('top-pages');
  const deviceEl = document.getElementById('device-breakdown');
  const topItemsEl = document.getElementById('top-items');
  const dwellEl = document.getElementById('page-dwell');
  const days = document.getElementById('range-select').value;

  overviewEl.textContent = 'Loading...';
  try {
    const response = await staffFetch(`/api/analytics/summary?days=${days}`);
    if (!response.ok) throw new Error(`Unable to load analytics (${response.status}).`);
    const summary = await response.json();

    const dayCount = summary.days.length || 1;
    const avgPerDay = Math.round(summary.totalViews / dayCount);
    const totalDeviceViews = summary.deviceBreakdown.reduce((sum, d) => sum + d.count, 0);
    const mobilePct = totalDeviceViews
      ? Math.round(((summary.deviceBreakdown.find((d) => d.device === 'mobile')?.count || 0) / totalDeviceViews) * 100)
      : null;
    overviewEl.innerHTML = `
      <div class="loyalty-card-summary">
        <span class="pill pill-approved">${summary.totalViews} total views</span>
        <span class="pill">${avgPerDay}/day average</span>
        ${mobilePct !== null ? `<span class="pill">${mobilePct}% mobile</span>` : ''}
      </div>
    `;

    const maxCount = Math.max(1, ...summary.days.map((d) => Object.values(d.counts).reduce((a, b) => a + b, 0)));
    chartEl.innerHTML = `
      <div class="analytics-bars">
        ${summary.days
          .map((d) => {
            const total = Object.values(d.counts).reduce((a, b) => a + b, 0);
            const heightPct = Math.max(2, Math.round((total / maxCount) * 100));
            const label = d.date.slice(5);
            return `
              <div class="analytics-bar-col" title="${escapeHtmlAnalytics(d.date)}: ${total} views">
                <div class="analytics-bar" style="height: ${heightPct}%"></div>
                <span class="analytics-bar-label">${escapeHtmlAnalytics(label)}</span>
              </div>
            `;
          })
          .join('')}
      </div>
    `;

    renderHbarTable(
      topPagesEl,
      summary.topPages.map((p) => ({ label: p.path, value: p.count })),
      { labelHeader: 'Page', valueHeader: 'Views' }
    );

    renderHbarTable(
      deviceEl,
      summary.deviceBreakdown.map((d) => ({ label: d.device, value: d.count })),
      { labelHeader: 'Device', valueHeader: 'Views' }
    );

    renderHbarTable(
      topItemsEl,
      summary.topItems.map((i) => ({ label: i.name, value: i.count })),
      { labelHeader: 'Item', valueHeader: 'Detail views' }
    );

    renderHbarTable(
      dwellEl,
      summary.pageDwell.map((d) => ({ label: d.path, value: d.avgSeconds, samples: d.samples })),
      {
        labelHeader: 'Page',
        valueHeader: 'Avg. time on page',
        formatValue: (v) => `${Math.round(v)}s`,
      }
    );
  } catch (error) {
    overviewEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

function renderMenuHealthTable(el, rows) {
  if (!rows.length) {
    el.innerHTML = '<p class="hint">None &mdash; nice work.</p>';
    return;
  }
  el.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Item</th><th>Category</th><th>Section</th><th></th></tr></thead>
        <tbody>
          ${rows
            .map(
              (r) => `
            <tr>
              <td>${escapeHtmlAnalytics(r.name)}</td>
              <td>${escapeHtmlAnalytics(r.categoryName)}</td>
              <td>${escapeHtmlAnalytics(r.section)}</td>
              <td><a class="cta-button secondary" style="padding: 0.35rem 0.7rem; font-size: 0.82rem;" href="/edit-item.html?id=${encodeURIComponent(r.id)}">Edit</a></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

async function loadMenuHealthReports() {
  const missingPriceEl = document.getElementById('missing-price-list');
  const missingPhotoEl = document.getElementById('missing-photo-list');
  missingPriceEl.innerHTML = '<p class="hint">Loading...</p>';
  missingPhotoEl.innerHTML = '<p class="hint">Loading...</p>';

  try {
    const response = await staffFetch('/api/menu');
    if (!response.ok) throw new Error(`Unable to load the menu (${response.status}).`);
    const data = await response.json();

    const missingPrice = [];
    const missingPhoto = [];
    (data.categories || []).forEach((category) => {
      (category.items || []).forEach((item) => {
        const row = { id: item.id, name: item.name, categoryName: category.name, section: category.section };
        if (item.price == null) missingPrice.push(row);
        if (!item.images || !item.images.length) missingPhoto.push(row);
      });
    });

    renderMenuHealthTable(missingPriceEl, missingPrice);
    renderMenuHealthTable(missingPhotoEl, missingPhoto);
  } catch (error) {
    const message = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
    missingPriceEl.innerHTML = message;
    missingPhotoEl.innerHTML = message;
  }
}

document.getElementById('range-select').addEventListener('change', loadAnalytics);
document.getElementById('reload-menu-health-btn').addEventListener('click', loadMenuHealthReports);

loadAnalytics();
loadMenuHealthReports();
