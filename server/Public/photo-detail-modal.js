function escapeHtmlPhotoDetail(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatPhotoDetailBytes(bytes) {
  if (bytes == null) return 'Unknown';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatPhotoDetailDate(iso) {
  if (!iso) return 'Unknown (uploaded before tracking was added)';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return 'Unknown';
  return parsed.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

(function () {
  const overlay = document.createElement('div');
  overlay.className = 'item-modal-overlay';
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="item-modal photo-detail-modal">
      <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
      <img class="photo-detail-image" src="" alt="" />
      <dl class="photo-detail-list"></dl>
    </div>
  `;
  document.body.appendChild(overlay);

  const img = overlay.querySelector('.photo-detail-image');
  const list = overlay.querySelector('.photo-detail-list');

  async function open(src) {
    img.src = src;
    overlay.hidden = false;
    list.innerHTML = '<div class="photo-detail-loading">Loading details&hellip;</div>';

    const filename = src.split('/').pop();
    try {
      const response = await fetch(`/api/uploads/${encodeURIComponent(filename)}/info`);
      if (!response.ok) throw new Error(`Couldn't load photo details (${response.status}).`);
      const info = await response.json();
      const resolution = info.width && info.height ? `${info.width} &times; ${info.height}px` : 'Unknown';
      list.innerHTML = `
        <div><dt>Resolution</dt><dd>${resolution}</dd></div>
        <div><dt>File size</dt><dd>${escapeHtmlPhotoDetail(formatPhotoDetailBytes(info.sizeBytes))}</dd></div>
        <div><dt>Date added</dt><dd>${escapeHtmlPhotoDetail(formatPhotoDetailDate(info.uploadedAt))}</dd></div>
        <div><dt>Added by</dt><dd>${escapeHtmlPhotoDetail(info.uploadedByName || 'Unknown (uploaded before tracking was added)')}</dd></div>
      `;
    } catch (error) {
      list.innerHTML = `<div class="photo-detail-error">${escapeHtmlPhotoDetail(error.message)}</div>`;
    }
  }

  function close() {
    overlay.hidden = true;
    img.src = '';
  }

  overlay.addEventListener('click', (event) => {
    if (event.target === overlay) close();
  });
  overlay.querySelector('.item-modal-close').addEventListener('click', close);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !overlay.hidden) close();
  });

  window.openPhotoDetail = open;
})();
