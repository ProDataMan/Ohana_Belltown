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

function renderSummaryPills(el, pills) {
  if (!el) return;
  el.innerHTML = pills.map((p) => `<span class="pill ${p.cls || ''}">${escapeHtmlAnalytics(p.label)}</span>`).join('');
}

async function loadAnalytics() {
  const overviewEl = document.getElementById('overview');
  const chartEl = document.getElementById('daily-chart');
  const topPagesEl = document.getElementById('top-pages');
  const deviceEl = document.getElementById('device-breakdown');
  const osEl = document.getElementById('os-breakdown');
  const browserEl = document.getElementById('browser-breakdown');
  const deviceModelEl = document.getElementById('device-model-breakdown');
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
    const peakDay = summary.days.reduce((best, d) => {
      const total = Object.values(d.counts).reduce((a, b) => a + b, 0);
      return !best || total > best.total ? { date: d.date, total } : best;
    }, null);
    renderSummaryPills(document.getElementById('daily-chart-summary'), [
      { label: `${summary.days.length} days shown` },
      ...(peakDay ? [{ label: `Peak: ${peakDay.date.slice(5)} (${peakDay.total} views)`, cls: 'pill-approved' }] : []),
    ]);

    renderSummaryPills(document.getElementById('top-pages-summary'), [
      { label: `${summary.topPages.length} pages tracked` },
      ...(summary.topPages[0] ? [{ label: `Most viewed: ${summary.topPages[0].path} (${summary.topPages[0].count})`, cls: 'pill-approved' }] : []),
    ]);

    renderSummaryPills(
      document.getElementById('device-breakdown-summary'),
      totalDeviceViews
        ? summary.deviceBreakdown
            .slice(0, 4)
            .map((d) => ({ label: `${Math.round((d.count / totalDeviceViews) * 100)}% ${d.device}` }))
        : [{ label: 'No data yet.' }]
    );

    const totalOSViews = summary.osBreakdown.reduce((sum, o) => sum + o.count, 0);
    renderSummaryPills(
      document.getElementById('os-breakdown-summary'),
      totalOSViews
        ? summary.osBreakdown.slice(0, 4).map((o) => ({ label: `${Math.round((o.count / totalOSViews) * 100)}% ${o.os}` }))
        : [{ label: 'No data yet.' }]
    );

    const totalBrowserViews = summary.browserBreakdown.reduce((sum, b) => sum + b.count, 0);
    renderSummaryPills(
      document.getElementById('browser-breakdown-summary'),
      totalBrowserViews
        ? summary.browserBreakdown.slice(0, 4).map((b) => ({ label: `${Math.round((b.count / totalBrowserViews) * 100)}% ${b.browser}` }))
        : [{ label: 'No data yet.' }]
    );

    renderSummaryPills(document.getElementById('device-model-breakdown-summary'), [
      { label: `${summary.deviceModelBreakdown.length} distinct Android models identified` },
      ...(summary.deviceModelBreakdown[0]
        ? [{ label: `Most common: ${summary.deviceModelBreakdown[0].model} (${summary.deviceModelBreakdown[0].count})`, cls: 'pill-approved' }]
        : []),
    ]);

    renderSummaryPills(document.getElementById('top-items-summary'), [
      { label: `${summary.topItems.reduce((sum, i) => sum + i.count, 0)} total detail views` },
      ...(summary.topItems[0] ? [{ label: `Most viewed: ${summary.topItems[0].name} (${summary.topItems[0].count})`, cls: 'pill-approved' }] : []),
    ]);

    const totalDwellSamples = summary.pageDwell.reduce((sum, d) => sum + d.samples, 0);
    const weightedAvg = totalDwellSamples
      ? Math.round(summary.pageDwell.reduce((sum, d) => sum + d.avgSeconds * d.samples, 0) / totalDwellSamples)
      : null;
    renderSummaryPills(document.getElementById('page-dwell-summary'), [
      ...(weightedAvg !== null ? [{ label: `${weightedAvg}s average across all tracked pages` }] : [{ label: 'No data yet.' }]),
      ...(summary.pageDwell[0] ? [{ label: `Longest: ${summary.pageDwell[0].path} (${Math.round(summary.pageDwell[0].avgSeconds)}s)`, cls: 'pill-approved' }] : []),
    ]);
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
      osEl,
      summary.osBreakdown.map((o) => ({ label: o.os, value: o.count })),
      { labelHeader: 'Operating System', valueHeader: 'Views' }
    );

    renderHbarTable(
      browserEl,
      summary.browserBreakdown.map((b) => ({ label: b.browser, value: b.count })),
      { labelHeader: 'Browser', valueHeader: 'Views' }
    );

    renderHbarTable(
      deviceModelEl,
      summary.deviceModelBreakdown.map((m) => ({ label: m.model, value: m.count })),
      { labelHeader: 'Model', valueHeader: 'Views' }
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

  const byCategory = new Map();
  rows.forEach((r) => {
    const key = `${r.section} — ${r.categoryName}`;
    if (!byCategory.has(key)) byCategory.set(key, { section: r.section, categoryName: r.categoryName, items: [] });
    byCategory.get(key).items.push(r);
  });
  const groups = Array.from(byCategory.values()).sort((a, b) => b.items.length - a.items.length);

  el.innerHTML = groups
    .map(
      (group) => `
    <div class="menu-health-group">
      <div class="editor-toolbar" style="margin-bottom: 0.4rem;">
        <h3 style="margin: 0; font-size: 1rem;">${escapeHtmlAnalytics(group.categoryName)} <span class="hint">(${escapeHtmlAnalytics(group.section)})</span></h3>
        <span class="pill pill-warning">${group.items.length} item${group.items.length === 1 ? '' : 's'}</span>
      </div>
      <div class="data-table">
        <table>
          <thead><tr><th>Item</th><th></th></tr></thead>
          <tbody>
            ${group.items
              .map(
                (r) => `
              <tr>
                <td>${escapeHtmlAnalytics(r.name)}</td>
                <td><a class="cta-button secondary" style="padding: 0.35rem 0.7rem; font-size: 0.82rem;" href="/edit-item.html?id=${encodeURIComponent(r.id)}">Edit</a></td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    </div>
  `
    )
    .join('');
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

    const totalItems = (data.categories || []).reduce((sum, c) => sum + (c.items || []).length, 0);
    renderSummaryPills(document.getElementById('missing-price-summary'), [
      { label: `${missingPrice.length} of ${totalItems} items missing a price`, cls: missingPrice.length ? 'pill-warning' : 'pill-approved' },
    ]);
    renderSummaryPills(document.getElementById('missing-photo-summary'), [
      { label: `${missingPhoto.length} of ${totalItems} items missing a photo`, cls: missingPhoto.length ? 'pill-warning' : 'pill-approved' },
    ]);

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
