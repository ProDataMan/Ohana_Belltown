async function refreshInboxCount() {
  const el = document.getElementById('inbox-count');
  try {
    const response = await staffFetch('/api/competitor-pricing/photos/inbox');
    if (!response.ok) throw new Error();
    const entries = await response.json();
    el.textContent = entries.length
      ? `${entries.length} photo${entries.length === 1 ? '' : 's'} waiting in the review inbox.`
      : 'Inbox is empty — nothing waiting on review right now.';
  } catch {
    el.textContent = '';
  }
}

async function uploadOnePhoto(file, row) {
  const statusEl = row.querySelector('.quick-upload-row-status');
  statusEl.textContent = 'Uploading…';

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();

    const inboxResponse = await staffFetch('/api/competitor-pricing/photos/inbox', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: result.url }),
    });
    if (!inboxResponse.ok) throw new Error(`Failed to queue for review (${inboxResponse.status}).`);

    statusEl.textContent = 'Added to review inbox ✓';
    statusEl.classList.add('status-ok');
    refreshInboxCount();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
}

document.getElementById('photo-input').addEventListener('change', (event) => {
  const files = Array.from(event.target.files || []);
  if (!files.length) return;
  const listEl = document.getElementById('upload-list');

  files.forEach((file) => {
    const row = document.createElement('div');
    row.className = 'quick-upload-row';
    row.innerHTML = `
      <img src="${URL.createObjectURL(file)}" alt="" />
      <span class="quick-upload-row-status">Starting…</span>
    `;
    listEl.prepend(row);
    uploadOnePhoto(file, row);
  });

  // Let the same file(s) be picked again later in the same visit without
  // needing a page reload first — browsers don't fire 'change' again for an
  // unchanged file list.
  event.target.value = '';
});

refreshInboxCount();
