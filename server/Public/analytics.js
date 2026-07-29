// Every section below Overview starts collapsed to a headline-only card in a
// grid (see .analytics-sections-grid) — clicking one, or a notification link
// like /analytics.html?section=feedback, expands just that section into a
// single full-width detail view instead. This is what makes deep links land
// exactly on the right section: only the active section's heavy content
// (charts/tables) ever renders, so there's nothing above it that can grow
// after the page loads and push it out of view.
function initAnalyticsLayout() {
  const container = document.getElementById('analytics-sections');
  const backLink = document.getElementById('analytics-back-link');
  const sections = Array.from(document.querySelectorAll('.analytics-section'));
  const activeKey = new URLSearchParams(window.location.search).get('section');
  const matched = activeKey && sections.some((s) => s.dataset.section === activeKey);

  sections.forEach((s) => {
    const isActive = matched && s.dataset.section === activeKey;
    s.hidden = matched && !isActive;
    s.classList.toggle('expanded', isActive);
  });
  container.classList.toggle('analytics-sections-grid', !matched);
  container.classList.toggle('analytics-sections-detail', matched);
  backLink.hidden = !matched;
}

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

async function loadCompetitorPricingReport() {
  const summaryEl = document.getElementById('competitor-pricing-summary');
  const listEl = document.getElementById('competitor-pricing-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';

  try {
    const response = await staffFetch('/api/competitor-pricing/report');
    if (!response.ok) throw new Error(`Unable to load the pricing report (${response.status}).`);
    const rows = await response.json();

    const priced = rows.filter((r) => r.ourPrice != null && r.competitorAverage != null);
    const above = priced.filter((r) => r.deltaVsAverage > 0).length;
    const below = priced.filter((r) => r.deltaVsAverage < 0).length;
    renderSummaryPills(summaryEl, [
      { label: `${rows.length} comparison${rows.length === 1 ? '' : 's'} tracked` },
      ...(priced.length ? [{ label: `${above} above average, ${below} below`, cls: above > below ? 'pill-warning' : 'pill-approved' }] : []),
    ]);

    if (!rows.length) {
      listEl.innerHTML = '<p class="hint">No comparison groups yet — set them up on <a href="/competitor-pricing-admin.html">Competitor Pricing</a>.</p>';
      return;
    }

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Comparison</th><th>Our Price</th><th>Competitor Avg</th><th>Range</th><th>Vs. Average</th></tr></thead>
          <tbody>
            ${rows
              .map((row) => {
                const ourPriceText = row.ourPrice != null ? `$${row.ourPrice.toFixed(2)}` : '<span class="hint">not linked</span>';
                const avgText = row.competitorAverage != null ? `$${row.competitorAverage.toFixed(2)} (${row.competitorCount})` : '<span class="hint">no data yet</span>';
                const rangeText = row.competitorMin != null ? `$${row.competitorMin.toFixed(2)}&ndash;$${row.competitorMax.toFixed(2)}` : '';
                let deltaText = '<span class="hint">&mdash;</span>';
                if (row.deltaVsAverage != null) {
                  const sign = row.deltaVsAverage > 0 ? '+' : '';
                  const pillClass = row.deltaVsAverage > 0 ? 'pill-denied' : 'pill-approved';
                  deltaText = `<span class="pill ${pillClass}">${sign}$${row.deltaVsAverage.toFixed(2)} (${sign}${row.deltaPercentVsAverage.toFixed(0)}%)</span>`;
                }
                return `
                <tr>
                  <td>${escapeHtmlAnalytics(row.label)}${row.ourMenuItemName ? `<div class="hint">${escapeHtmlAnalytics(row.ourMenuItemName)}</div>` : ''}</td>
                  <td>${ourPriceText}</td>
                  <td>${avgText}</td>
                  <td>${rangeText}</td>
                  <td>${deltaText}</td>
                </tr>
              `;
              })
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    summaryEl.innerHTML = '';
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

async function loadDeliveryStats() {
  const summaryEl = document.getElementById('delivery-stats-summary');
  const listEl = document.getElementById('delivery-stats');
  const days = document.getElementById('range-select').value;

  try {
    const response = await staffFetch(`/api/table-orders/delivery-stats?days=${days}`);
    if (!response.ok) throw new Error(`Unable to load delivery stats (${response.status}).`);
    const stats = await response.json();

    const fmt = (v) => (v == null ? '—' : `${Math.round(v)}m`);
    renderSummaryPills(summaryEl, [
      { label: `${stats.completedOrders} completed orders` },
      { label: `Avg wait: ${fmt(stats.overallAvgWaitMinutes)}` },
      { label: `Avg prep: ${fmt(stats.overallAvgPrepMinutes)}` },
      { label: `Avg total: ${fmt(stats.overallAvgTotalMinutes)}`, cls: 'pill-approved' },
    ]);

    if (!stats.items.length) {
      listEl.innerHTML = '<p class="hint">No completed table orders yet.</p>';
      return;
    }
    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Item</th><th>Orders</th><th>Avg Wait</th><th>Avg Prep</th><th>Avg Total</th></tr></thead>
          <tbody>
            ${stats.items
              .map(
                (i) => `
              <tr>
                <td>${escapeHtmlAnalytics(i.itemName)}</td>
                <td>${i.samples}</td>
                <td>${fmt(i.avgWaitMinutes)}</td>
                <td>${fmt(i.avgPrepMinutes)}</td>
                <td>${fmt(i.avgTotalMinutes)}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    summaryEl.innerHTML = '';
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

async function loadOccupancyStats() {
  const summaryEl = document.getElementById('table-occupancy-summary');
  const detailEl = document.getElementById('table-occupancy');
  const days = document.getElementById('range-select').value;

  try {
    const response = await staffFetch(`/api/table-orders/occupancy-stats?days=${days}`);
    if (!response.ok) throw new Error(`Unable to load table occupancy estimates (${response.status}).`);
    const stats = await response.json();

    const fmt = (v) => `${Math.round(v)}m`;
    renderSummaryPills(summaryEl, [
      { label: stats.isBaselineOnly ? 'No completed sessions yet' : `${stats.sessions} dining session${stats.sessions === 1 ? '' : 's'}` },
      { label: `Est. table occupancy: ${fmt(stats.averageEstimatedOccupancyMinutes)}`, cls: 'pill-approved' },
    ]);

    const waitPlusPrepLabel = stats.isBaselineOnly
      ? `~${fmt(stats.averageWaitPlusPrepMinutes)} (no completed orders yet — generic baseline)`
      : `${fmt(stats.averageWaitPlusPrepMinutes)} (real average from completed orders)`;

    detailEl.innerHTML = `
      ${stats.isBaselineOnly ? '<p class="hint">Showing a generic single-entree example — this will switch to your own restaurant\'s real data once dining sessions complete.</p>' : ''}
      <div class="data-table">
        <table>
          <thead><tr><th>What's driving the estimate</th><th>Minutes</th></tr></thead>
          <tbody>
            <tr><td>Deciding what to order before the first order is placed</td><td>${fmt(stats.arrivalToOrderMinutes)}</td></tr>
            <tr><td>Wait + kitchen prep time</td><td>${waitPlusPrepLabel}</td></tr>
            <tr><td>Eating/drinking what was ordered</td><td>${fmt(stats.averageEstimatedEatingMinutes)}</td></tr>
            <tr><td>Conversation, paying, and getting up to leave</td><td>${fmt(stats.socialOverheadMinutes)}</td></tr>
            <tr><td><strong>Total estimated table occupancy</strong></td><td><strong>${fmt(stats.averageEstimatedOccupancyMinutes)}</strong></td></tr>
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    summaryEl.innerHTML = '';
    detailEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

function categoryLabel(category) {
  return { website: 'Website', food: 'Food', service: 'Service', other: 'Other' }[category] || category;
}

async function loadFeedback() {
  const summaryEl = document.getElementById('feedback-summary');
  const listEl = document.getElementById('feedback-list');
  try {
    const response = await staffFetch('/api/feedback?days=30');
    if (!response.ok) throw new Error(`Unable to load feedback (${response.status}).`);
    const entries = await response.json();

    const ratings = entries.map((e) => e.rating).filter((r) => r != null);
    const avg = ratings.length ? (ratings.reduce((a, b) => a + b, 0) / ratings.length).toFixed(1) : null;
    const unacknowledged = entries.filter((e) => !e.acknowledged).length;
    renderSummaryPills(summaryEl, [
      { label: `${entries.length} submissions (last 30 days)` },
      ...(avg !== null ? [{ label: `Avg rating: ${avg} / 5` }] : []),
      ...(unacknowledged ? [{ label: `${unacknowledged} unread`, cls: 'pill-warning' }] : [{ label: 'All read', cls: 'pill-approved' }]),
    ]);

    if (!entries.length) {
      listEl.innerHTML = '<p class="hint">No feedback yet.</p>';
      return;
    }
    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>When</th><th>Category</th><th>Rating</th><th>Message</th><th>Page</th><th>Contact</th></tr></thead>
          <tbody>
            ${entries
              .map(
                (e) => `
              <tr>
                <td>${new Date(e.createdAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</td>
                <td><span class="pill ${e.acknowledged ? '' : 'pill-warning'}">${escapeHtmlAnalytics(categoryLabel(e.category))}</span></td>
                <td>${e.rating != null ? `${e.rating}/5` : '—'}</td>
                <td>${escapeHtmlAnalytics(e.message)}</td>
                <td>${escapeHtmlAnalytics(e.page || '')}</td>
                <td>${escapeHtmlAnalytics(e.contactEmail || '')}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    summaryEl.innerHTML = '';
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

document.getElementById('acknowledge-feedback-btn').addEventListener('click', async () => {
  await staffFetch('/api/feedback/acknowledge-all', { method: 'POST' });
  await loadFeedback();
});
document.getElementById('reload-feedback-btn').addEventListener('click', loadFeedback);

document.getElementById('range-select').addEventListener('change', loadAnalytics);
document.getElementById('range-select').addEventListener('change', loadDeliveryStats);
document.getElementById('range-select').addEventListener('change', loadOccupancyStats);
document.getElementById('reload-menu-health-btn').addEventListener('click', loadMenuHealthReports);
document.getElementById('reload-competitor-pricing-btn').addEventListener('click', loadCompetitorPricingReport);

initAnalyticsLayout();
loadAnalytics();
loadMenuHealthReports();
loadCompetitorPricingReport();
loadDeliveryStats();
loadOccupancyStats();
loadFeedback();
