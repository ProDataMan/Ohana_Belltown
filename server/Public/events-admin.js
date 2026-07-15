function escapeHtmlEvents(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const listEl = document.getElementById('events-list');
const statusEl = document.getElementById('status');
const saveStatusEl = document.getElementById('save-status');

function eventRow(item) {
  const row = document.createElement('div');
  row.className = 'category';
  row.dataset.id = item.id;
  row.innerHTML = `
    <div class="items">
      <label>Title
        <input type="text" class="event-title" value="${escapeHtmlEvents(item.title)}" />
      </label>
      <label>Schedule
        <input type="text" class="event-schedule" value="${escapeHtmlEvents(item.schedule)}" />
      </label>
      <label>Description
        <textarea class="event-description" rows="2">${escapeHtmlEvents(item.description || '')}</textarea>
      </label>
      <label class="featured-toggle">
        <input type="checkbox" class="event-active" ${item.active ? 'checked' : ''} />
        Currently active
      </label>
      <div class="cta-row">
        <button type="button" class="secondary event-remove-btn">Remove</button>
      </div>
    </div>
  `;
  row.querySelector('.event-remove-btn').addEventListener('click', () => row.remove());
  return row;
}

function renderEvents(events) {
  listEl.innerHTML = '';
  events.forEach((item) => listEl.appendChild(eventRow(item)));
}

function collectEvents() {
  return Array.from(listEl.children).map((row) => ({
    id: row.dataset.id,
    title: row.querySelector('.event-title').value.trim(),
    schedule: row.querySelector('.event-schedule').value.trim(),
    description: row.querySelector('.event-description').value.trim() || null,
    active: row.querySelector('.event-active').checked,
  }));
}

async function loadEvents() {
  setStatus(statusEl, 'Loading...', false);
  try {
    const response = await fetch('/api/events');
    if (!response.ok) throw new Error('Unable to load events.');
    const data = await response.json();
    renderEvents(data.events || []);
    setStatus(statusEl, '', false);
  } catch (error) {
    setStatus(statusEl, error.message, true);
  }
}

document.getElementById('reload-btn').addEventListener('click', loadEvents);

document.getElementById('add-event-btn').addEventListener('click', () => {
  listEl.appendChild(
    eventRow({ id: crypto.randomUUID(), title: '', schedule: '', description: '', active: true })
  );
});

document.getElementById('save-btn').addEventListener('click', async () => {
  setStatus(saveStatusEl, 'Saving...', false);
  try {
    const events = collectEvents();
    const response = await staffFetch('/api/events', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ events }),
    });
    if (!response.ok) throw new Error(`Save failed (${response.status}).`);
    setStatus(saveStatusEl, 'Saved!', false);
  } catch (error) {
    setStatus(saveStatusEl, error.message, true);
  }
});

loadEvents();
