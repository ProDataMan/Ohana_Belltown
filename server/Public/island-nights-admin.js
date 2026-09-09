function escapeHtmlIslandNights(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setIslandNightsStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const listEl = document.getElementById('performers-list');
const statusEl = document.getElementById('status');
let performers = [];

function formatPerformerDate(dateStr) {
  const [year, month, day] = dateStr.split('-').map(Number);
  if (!year) return dateStr;
  return new Date(year, month - 1, day).toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

async function loadPerformers() {
  setIslandNightsStatus(statusEl, 'Loading...', false);
  try {
    const response = await fetch('/api/island-nights');
    if (!response.ok) throw new Error(`Failed to load (${response.status}).`);
    performers = await response.json();
    setIslandNightsStatus(statusEl, '', false);
    renderPerformers();
  } catch (error) {
    setIslandNightsStatus(statusEl, error.message, true);
  }
}

function renderPerformers() {
  if (!performers.length) {
    listEl.innerHTML = '<p class="hint">No performers booked yet — add one below.</p>';
    return;
  }

  listEl.innerHTML = performers
    .map(
      (p, index) => `
    <div class="panel" data-index="${index}" data-id="${escapeHtmlIslandNights(p.id)}" style="margin-bottom: 1rem;">
      <div class="cta-row" style="justify-content: space-between; align-items: flex-end;">
        <label>Date
          <input type="date" class="performer-date-input" value="${escapeHtmlIslandNights(p.date)}" />
        </label>
        <span class="hint performer-date-label">${p.date ? escapeHtmlIslandNights(formatPerformerDate(p.date)) : ''}</span>
        <button type="button" class="secondary performer-remove-btn">Remove</button>
      </div>
      <label>Performer name
        <input type="text" class="performer-name-input" value="${escapeHtmlIslandNights(p.performerName)}" placeholder="e.g. The Coconut Wireless" />
      </label>
      <label>Bio / note (optional)
        <textarea class="performer-bio-input" rows="2">${escapeHtmlIslandNights(p.bio || '')}</textarea>
      </label>

      <p class="hint" style="margin-bottom: 0.4rem;">Photos</p>
      <div class="item-thumb-gallery">
        ${(p.photos || [])
          .map(
            (url, photoIndex) => `
          <div class="menu-photo-item">
            <div class="item-thumb-wrap">
              <a href="${escapeHtmlIslandNights(url)}" target="_blank" rel="noopener">
                <img class="item-thumb" src="${escapeHtmlIslandNights(url)}" alt="${escapeHtmlIslandNights(p.performerName)}" />
              </a>
              <button type="button" class="thumb-remove-btn performer-photo-remove-btn" data-photo-index="${photoIndex}" aria-label="Remove this photo">&times;</button>
            </div>
          </div>
        `
          )
          .join('')}
      </div>
      <label class="photo-upload-btn">
        + Add Photo
        <input type="file" accept="image/*" class="performer-photo-upload-input" hidden />
      </label>
      <p class="hint performer-photo-status"></p>

      <p class="hint" style="margin: 0.8rem 0 0.4rem;">Video (with sound)</p>
      ${p.videoURL
        ? `<div class="item-thumb-wrap" style="max-width: 320px;">
             <video src="${escapeHtmlIslandNights(p.videoURL)}" controls style="max-width: 100%; border-radius: 8px;"></video>
             <button type="button" class="thumb-remove-btn performer-video-remove-btn" aria-label="Remove this video">&times;</button>
           </div>`
        : '<p class="hint">No video yet.</p>'}
      <label class="photo-upload-btn">
        ${p.videoURL ? 'Replace Video' : '+ Add Video'}
        <input type="file" accept="video/mp4,video/quicktime,video/webm,video/x-m4v" class="performer-video-upload-input" hidden />
      </label>
      <p class="hint performer-video-status"></p>

      <div class="save-row">
        <button type="button" class="performer-save-btn">Save</button>
        <p class="status performer-save-status"></p>
      </div>
    </div>
  `
    )
    .join('');

  wirePerformerCard();
}

function wirePerformerCard() {
  listEl.querySelectorAll('.performer-remove-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const card = btn.closest('[data-id]');
      const id = card.dataset.id;
      if (!confirm('Remove this performer?')) return;
      if (id) {
        try {
          const response = await staffFetch(`/api/island-nights/${id}`, { method: 'DELETE' });
          if (!response.ok) throw new Error(`Failed (${response.status}).`);
        } catch (error) {
          alert(error.message);
          return;
        }
      }
      const index = Number(card.dataset.index);
      performers.splice(index, 1);
      renderPerformers();
    });
  });

  listEl.querySelectorAll('.performer-photo-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const card = btn.closest('[data-id]');
      const index = Number(card.dataset.index);
      const photoIndex = Number(btn.dataset.photoIndex);
      performers[index].photos.splice(photoIndex, 1);
      renderPerformers();
    });
  });

  listEl.querySelectorAll('.performer-video-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const card = btn.closest('[data-id]');
      const index = Number(card.dataset.index);
      performers[index].videoURL = null;
      renderPerformers();
    });
  });

  listEl.querySelectorAll('.performer-photo-upload-input').forEach((input) => {
    input.addEventListener('change', (event) => uploadPerformerPhoto(event));
  });

  listEl.querySelectorAll('.performer-video-upload-input').forEach((input) => {
    input.addEventListener('change', (event) => uploadPerformerVideo(event));
  });

  listEl.querySelectorAll('.performer-save-btn').forEach((btn) => {
    btn.addEventListener('click', () => savePerformer(btn.closest('[data-id]')));
  });

  listEl.querySelectorAll('.performer-date-input').forEach((input) => {
    input.addEventListener('input', () => {
      const label = input.closest('.cta-row').querySelector('.performer-date-label');
      const isWednesday = input.value && new Date(input.value + 'T00:00:00').getDay() === 3;
      label.textContent = input.value ? formatPerformerDate(input.value) : '';
      label.classList.toggle('status-error', Boolean(input.value) && !isWednesday);
      if (input.value && !isWednesday) label.textContent += ' — not a Wednesday!';
    });
  });
}

async function uploadPerformerPhoto(event) {
  const file = event.target.files[0];
  if (!file) return;
  const card = event.target.closest('[data-id]');
  const index = Number(card.dataset.index);
  const statusEl = card.querySelector('.performer-photo-status');
  setIslandNightsStatus(statusEl, 'Uploading...', false);

  const formData = new FormData();
  formData.append('image', file);
  try {
    const response = await staffFetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();
    performers[index].photos = [...(performers[index].photos || []), result.url];
    setIslandNightsStatus(statusEl, '', false);
    renderPerformers();
  } catch (error) {
    setIslandNightsStatus(statusEl, error.message, true);
  }
}

async function uploadPerformerVideo(event) {
  const file = event.target.files[0];
  if (!file) return;
  const card = event.target.closest('[data-id]');
  const index = Number(card.dataset.index);
  const statusEl = card.querySelector('.performer-video-status');
  setIslandNightsStatus(statusEl, `Uploading (${(file.size / 1024 / 1024).toFixed(1)}MB, this can take a bit)...`, false);

  const formData = new FormData();
  formData.append('video', file);
  try {
    const response = await staffFetch('/api/upload-video', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();
    performers[index].videoURL = result.url;
    setIslandNightsStatus(statusEl, '', false);
    renderPerformers();
  } catch (error) {
    setIslandNightsStatus(statusEl, error.message, true);
  }
}

async function savePerformer(card) {
  const index = Number(card.dataset.index);
  const id = card.dataset.id;
  const date = card.querySelector('.performer-date-input').value;
  const performerName = card.querySelector('.performer-name-input').value.trim();
  const bio = card.querySelector('.performer-bio-input').value.trim() || null;
  const statusEl = card.querySelector('.performer-save-status');

  if (!date || !performerName) {
    return setIslandNightsStatus(statusEl, 'Date and performer name are required.', true);
  }

  const body = {
    date,
    performerName,
    bio,
    photos: performers[index].photos || [],
    videoURL: performers[index].videoURL || null,
  };

  setIslandNightsStatus(statusEl, 'Saving...', false);
  try {
    const isNew = !id;
    const response = await staffFetch(isNew ? '/api/island-nights' : `/api/island-nights/${id}`, {
      method: isNew ? 'POST' : 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const responseBody = await response.json().catch(() => ({}));
      throw new Error(responseBody.reason || `Save failed (${response.status}).`);
    }
    performers[index] = await response.json();
    setIslandNightsStatus(statusEl, 'Saved!', false);
    renderPerformers();
  } catch (error) {
    setIslandNightsStatus(statusEl, error.message, true);
  }
}

document.getElementById('add-performer-btn').addEventListener('click', () => {
  performers.push({ id: null, date: '', performerName: '', bio: '', photos: [], videoURL: null });
  renderPerformers();
});

document.getElementById('reload-btn').addEventListener('click', loadPerformers);

loadPerformers();
