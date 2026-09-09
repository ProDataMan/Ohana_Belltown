function escapeHtmlIslandNightsPublic(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatIslandNightsDate(dateStr) {
  const [year, month, day] = dateStr.split('-').map(Number);
  if (!year) return dateStr;
  return new Date(year, month - 1, day).toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

function formatIslandNightsTime(timeStr) {
  if (!timeStr) return null;
  const [hours, minutes] = timeStr.split(':').map(Number);
  if (Number.isNaN(hours)) return null;
  return new Date(2000, 0, 1, hours, minutes).toLocaleTimeString(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  });
}

async function loadIslandNightsPerformers() {
  const section = document.getElementById('island-nights-performers-section');
  const listEl = document.getElementById('island-nights-performers-list');
  if (!section || !listEl) return;

  try {
    const response = await fetch('/api/island-nights/upcoming');
    if (!response.ok) return;
    const performers = await response.json();
    if (!performers.length) return;

    listEl.innerHTML = performers
      .map(
        (p) => `
      <div class="performer-card">
        <p class="eyebrow">${escapeHtmlIslandNightsPublic(formatIslandNightsDate(p.date))}${formatIslandNightsTime(p.startTime) ? ' &middot; ' + escapeHtmlIslandNightsPublic(formatIslandNightsTime(p.startTime)) : ''}</p>
        <h3>${escapeHtmlIslandNightsPublic(p.performerName)}</h3>
        ${p.bio ? `<p>${escapeHtmlIslandNightsPublic(p.bio)}</p>` : ''}
        ${
          (p.photos || []).length
            ? `<div class="performer-photos">
                 ${p.photos
                   .map(
                     (url) => `
                   <button type="button" class="gallery-item" data-src="${escapeHtmlIslandNightsPublic(url)}" data-caption="${escapeHtmlIslandNightsPublic(p.performerName)}">
                     <img src="${escapeHtmlIslandNightsPublic(url)}" alt="${escapeHtmlIslandNightsPublic(p.performerName)}" loading="lazy" />
                   </button>
                 `
                   )
                   .join('')}
               </div>`
            : ''
        }
        ${p.videoURL ? `<video controls preload="metadata" src="${escapeHtmlIslandNightsPublic(p.videoURL)}"></video>` : ''}
      </div>
    `
      )
      .join('');

    listEl.querySelectorAll('.gallery-item').forEach((el) => {
      el.addEventListener('click', () => {
        window.openLightbox(el.dataset.src, el.dataset.caption);
      });
    });

    section.hidden = false;
  } catch {
    // Best-effort — the static weekly schedule above already covers the
    // essentials, so a failed fetch here just means no "Coming Up" section.
  }
}

loadIslandNightsPerformers();
