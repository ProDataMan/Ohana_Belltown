function escapeHtmlAnalytics(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadAnalytics() {
  const overviewEl = document.getElementById('overview');
  const chartEl = document.getElementById('daily-chart');
  const topPagesEl = document.getElementById('top-pages');
  const days = document.getElementById('range-select').value;

  overviewEl.textContent = 'Loading...';
  try {
    const response = await staffFetch(`/api/analytics/summary?days=${days}`);
    if (!response.ok) throw new Error(`Unable to load analytics (${response.status}).`);
    const summary = await response.json();

    const dayCount = summary.days.length || 1;
    const avgPerDay = Math.round(summary.totalViews / dayCount);
    overviewEl.innerHTML = `
      <div class="loyalty-card-summary">
        <span class="pill pill-approved">${summary.totalViews} total views</span>
        <span class="pill">${avgPerDay}/day average</span>
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

    if (!summary.topPages.length) {
      topPagesEl.innerHTML = '<p class="hint">No data yet.</p>';
    } else {
      const maxPageCount = summary.topPages[0].count;
      topPagesEl.innerHTML = `
        <div class="data-table">
          <table>
            <thead><tr><th>Page</th><th>Views</th><th></th></tr></thead>
            <tbody>
              ${summary.topPages
                .map(
                  (p) => `
                <tr>
                  <td>${escapeHtmlAnalytics(p.path)}</td>
                  <td>${p.count}</td>
                  <td style="width: 40%;">
                    <div class="analytics-hbar" style="width: ${Math.max(4, Math.round((p.count / maxPageCount) * 100))}%"></div>
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
  } catch (error) {
    overviewEl.innerHTML = `<p class="status status-error">${escapeHtmlAnalytics(error.message)}</p>`;
  }
}

document.getElementById('range-select').addEventListener('change', loadAnalytics);

loadAnalytics();
