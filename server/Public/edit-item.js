const TAGS = [
  { key: 'vegetarian', label: 'Vegetarian friendly' },
  { key: 'gluten-free-available', label: 'Gluten-free available on request' },
  { key: 'shellfish', label: 'Contains shellfish' },
  { key: 'fish', label: 'Contains fish' },
  { key: 'peanuts', label: 'Contains peanuts' },
  { key: 'egg', label: 'Contains egg' },
  { key: 'soy', label: 'Contains soy' },
  { key: 'wheat', label: 'Contains wheat' },
  { key: 'corn', label: 'Contains corn' },
  { key: 'sesame', label: 'Contains sesame' },
  { key: 'dairy', label: 'Contains dairy' },
  { key: 'raw', label: 'May contain raw/undercooked items' },
];

function escapeAttrItem(value) {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}

function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const itemId = new URLSearchParams(window.location.search).get('id');
const statusEl = document.getElementById('status');
const panelEl = document.getElementById('editor-panel');
let currentImages = [];
let currentModifiers = [];
let currentChoiceGroups = [];
let additionsCatalog = [];

async function loadAdditionsCatalog() {
  const select = document.getElementById('catalog-modifier-select');
  try {
    const response = await staffFetch('/api/additions-catalog');
    if (!response.ok) throw new Error(`Unable to load the additions catalog (${response.status}).`);
    additionsCatalog = await response.json();
    additionsCatalog.sort((a, b) => a.name.localeCompare(b.name));
    select.innerHTML =
      '<option value="">— pick an existing addition —</option>' +
      additionsCatalog
        .map((a) => `<option value="${escapeAttrItem(a.id)}">${escapeAttrItem(a.name)} (+$${Number(a.priceDelta).toFixed(2)})</option>`)
        .join('');
  } catch {
    // The free-text add-on inputs still work without the catalog.
  }
}

document.getElementById('catalog-modifier-select').addEventListener('change', (event) => {
  const picked = additionsCatalog.find((a) => a.id === event.target.value);
  if (!picked) return;
  document.getElementById('new-modifier-name').value = picked.name;
  document.getElementById('new-modifier-price').value = picked.priceDelta;
  event.target.value = '';
});

/// Saves a brand-new addition name to the shared catalog so other items can
/// reuse it later — fire-and-forget, since this shouldn't block adding the
/// modifier to the item itself if it fails.
async function addToCatalogIfNew(name, priceDelta) {
  if (additionsCatalog.some((a) => a.name.toLowerCase() === name.toLowerCase())) return;
  const updated = [...additionsCatalog, { id: (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`, name, priceDelta }];
  try {
    const response = await staffFetch('/api/additions-catalog', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updated),
    });
    if (response.ok) await loadAdditionsCatalog();
  } catch {
    // Not critical — the modifier is still added to this item either way.
  }
}

function renderModifiersList() {
  const el = document.getElementById('modifiers-list');
  if (!currentModifiers.length) {
    el.innerHTML = '<p class="hint">No add-ons yet.</p>';
    return;
  }
  el.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Add-on</th><th>Extra price</th><th></th></tr></thead>
        <tbody>
          ${currentModifiers
            .map(
              (m, i) => `
            <tr>
              <td>${escapeAttrItem(m.name)}</td>
              <td>+$${Number(m.priceDelta).toFixed(2)}</td>
              <td><button type="button" class="secondary remove-modifier-btn" data-index="${i}" style="padding: 0.35rem 0.7rem; font-size: 0.82rem;">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  el.querySelectorAll('.remove-modifier-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      currentModifiers.splice(Number(btn.dataset.index), 1);
      renderModifiersList();
    });
  });
}

function addModifier() {
  const nameInput = document.getElementById('new-modifier-name');
  const priceInput = document.getElementById('new-modifier-price');
  const name = nameInput.value.trim();
  const priceDelta = Number.parseFloat(priceInput.value);
  if (!name || Number.isNaN(priceDelta)) return;
  currentModifiers.push({ id: (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`, name, priceDelta });
  renderModifiersList();
  addToCatalogIfNew(name, priceDelta);
  nameInput.value = '';
  priceInput.value = '';
  nameInput.focus();
}

function renderChoiceGroupsList() {
  const el = document.getElementById('choice-groups-list');
  if (!currentChoiceGroups.length) {
    el.innerHTML = '<p class="hint">No required choices yet.</p>';
    return;
  }
  el.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Choice</th><th>Options</th><th></th></tr></thead>
        <tbody>
          ${currentChoiceGroups
            .map(
              (g, i) => `
            <tr>
              <td>${escapeAttrItem(g.label)}</td>
              <td>${g.options.map(escapeAttrItem).join(', ')}</td>
              <td><button type="button" class="secondary remove-choice-group-btn" data-index="${i}" style="padding: 0.35rem 0.7rem; font-size: 0.82rem;">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  el.querySelectorAll('.remove-choice-group-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      currentChoiceGroups.splice(Number(btn.dataset.index), 1);
      renderChoiceGroupsList();
    });
  });
}

function addChoiceGroup() {
  const labelInput = document.getElementById('new-choice-group-label');
  const optionsInput = document.getElementById('new-choice-group-options');
  const label = labelInput.value.trim();
  const options = optionsInput.value.split(',').map((s) => s.trim()).filter(Boolean);
  if (!label || options.length < 2) return;
  currentChoiceGroups.push({ id: (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`, label, options });
  renderChoiceGroupsList();
  labelInput.value = '';
  optionsInput.value = '';
  labelInput.focus();
}

function renderThumbGallery() {
  const gallery = document.getElementById('item-thumb-gallery');
  gallery.innerHTML = currentImages
    .map(
      (src, i) => `
        <div class="item-thumb-wrap">
          <img class="item-thumb" src="${escapeAttrItem(src)}" alt="" />
          ${
            i === 0
              ? '<span class="thumb-featured-badge" title="Featured photo">&#9733;</span>'
              : `<button type="button" class="thumb-feature-btn" data-index="${i}" title="Set as featured">&#9733;</button>`
          }
          <button type="button" class="thumb-remove-btn" data-index="${i}" title="Remove photo">&times;</button>
        </div>
      `
    )
    .join('');

  gallery.querySelectorAll('.thumb-feature-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const idx = Number(btn.dataset.index);
      const [chosen] = currentImages.splice(idx, 1);
      currentImages.unshift(chosen);
      renderThumbGallery();
    });
  });
  gallery.querySelectorAll('.thumb-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const idx = Number(btn.dataset.index);
      currentImages.splice(idx, 1);
      renderThumbGallery();
    });
  });
}

async function uploadItemImage(event) {
  const file = event.target.files[0];
  if (!file) return;
  const photoStatusEl = document.getElementById('photo-status');
  setStatus(photoStatusEl, 'Uploading...', false);

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();
    currentImages.push(result.url);
    renderThumbGallery();
    setStatus(photoStatusEl, 'Photo added.', false);
  } catch (error) {
    setStatus(photoStatusEl, error.message, true);
  } finally {
    event.target.value = '';
  }
}

let googlePhotosForPicker = null;

async function openGooglePhotoPicker() {
  let picker = document.getElementById('google-photo-picker');
  if (!picker) {
    picker = document.createElement('div');
    picker.id = 'google-photo-picker';
    picker.className = 'item-modal-overlay';
    picker.hidden = true;
    picker.innerHTML = `
      <div class="item-modal google-picker-modal">
        <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
        <h3 class="item-modal-name">Choose a photo from Google</h3>
        <p class="hint">These are the photos currently on Ohana's Google Business listing &mdash; only pick one if you're sure it actually shows this dish.</p>
        <div class="google-picker-grid"></div>
      </div>
    `;
    document.body.appendChild(picker);
    picker.addEventListener('click', (event) => {
      if (event.target === picker) picker.hidden = true;
    });
    picker.querySelector('.item-modal-close').addEventListener('click', () => {
      picker.hidden = true;
    });
  }

  const grid = picker.querySelector('.google-picker-grid');
  grid.innerHTML = '<p class="hint">Loading...</p>';
  picker.hidden = false;

  if (!googlePhotosForPicker) {
    try {
      const response = await fetch('/api/places-photos');
      googlePhotosForPicker = response.ok ? await response.json() : [];
    } catch {
      googlePhotosForPicker = [];
    }
  }

  if (!googlePhotosForPicker.length) {
    grid.innerHTML = '<p class="hint">No Google photos are available right now.</p>';
    return;
  }

  grid.innerHTML = googlePhotosForPicker
    .map(
      (p, i) =>
        `<img src="${escapeAttrItem(p.url)}" data-index="${i}" alt="Photo by ${escapeAttrItem(p.attributionName)}" title="Photo by ${escapeAttrItem(p.attributionName)}" />`
    )
    .join('');

  grid.querySelectorAll('img').forEach((imgEl) => {
    imgEl.addEventListener('click', () => {
      const photo = googlePhotosForPicker[Number(imgEl.dataset.index)];
      if (!currentImages.includes(photo.url)) {
        currentImages.push(photo.url);
        renderThumbGallery();
      }
      picker.hidden = true;
    });
  });
}

async function loadItem() {
  if (!itemId) {
    setStatus(statusEl, 'No item specified — go back to the menu editor and use an edit link.', true);
    return;
  }
  setStatus(statusEl, 'Loading...', false);
  try {
    const response = await fetch(`/api/menu/items/${encodeURIComponent(itemId)}`);
    if (!response.ok) throw new Error(`Unable to load this item (${response.status}).`);
    const { item, categoryName, section } = await response.json();

    document.getElementById('item-category-eyebrow').textContent = `${categoryName} — ${section}`;
    document.getElementById('item-name-input').value = item.name || '';
    document.getElementById('item-desc-input').value = item.description || '';
    document.getElementById('item-price-input').value = item.price != null ? Number(item.price).toFixed(2) : '';
    document.getElementById('item-featured-input').checked = Boolean(item.featured);
    document.getElementById('item-sold-out-input').checked = item.available === false;
    document.getElementById('item-happy-hour-input').checked = Boolean(item.happyHour);
    document.getElementById('item-requires-modifier-input').checked = Boolean(item.requiresModifierSelection);

    currentImages = item.images || [];
    renderThumbGallery();

    currentModifiers = item.modifiers || [];
    renderModifiersList();

    currentChoiceGroups = item.choiceGroups || [];
    renderChoiceGroupsList();

    const tagsGrid = document.getElementById('item-tags-grid');
    tagsGrid.innerHTML = TAGS.map(
      (t) => `
        <label class="tag-checkbox">
          <input type="checkbox" class="item-tag" value="${t.key}" ${(item.tags || []).includes(t.key) ? 'checked' : ''} />
          ${t.label}
        </label>
      `
    ).join('');

    document.title = `Edit ${item.name} — Ohana Belltown`;
    panelEl.hidden = false;
    setStatus(statusEl, '', false);
  } catch (error) {
    setStatus(statusEl, error.message, true);
  }
}

async function saveItem() {
  const saveStatusEl = document.getElementById('save-status');
  const name = document.getElementById('item-name-input').value.trim();
  if (!name) return setStatus(saveStatusEl, 'Item name is required.', true);

  const priceRaw = document.getElementById('item-price-input').value.trim();
  const body = {
    name,
    description: document.getElementById('item-desc-input').value.trim() || null,
    price: priceRaw === '' ? null : Number.parseFloat(priceRaw),
    images: currentImages,
    tags: Array.from(document.querySelectorAll('.item-tag:checked')).map((cb) => cb.value),
    featured: document.getElementById('item-featured-input').checked,
    available: !document.getElementById('item-sold-out-input').checked,
    happyHour: document.getElementById('item-happy-hour-input').checked,
    modifiers: currentModifiers,
    choiceGroups: currentChoiceGroups,
    requiresModifierSelection: document.getElementById('item-requires-modifier-input').checked,
  };

  document.getElementById('save-btn').disabled = true;
  setStatus(saveStatusEl, 'Saving...', false);
  try {
    const response = await staffFetch(`/api/menu/items/${encodeURIComponent(itemId)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`Save failed (${response.status}).`);
    setStatus(saveStatusEl, 'Saved! Returning to the menu...', false);
    setTimeout(() => { window.location.href = '/menu'; }, 700);
  } catch (error) {
    setStatus(saveStatusEl, error.message, true);
    document.getElementById('save-btn').disabled = false;
  }
}

async function deleteItem() {
  const name = document.getElementById('item-name-input').value.trim() || 'this item';
  if (!confirm(`Delete "${name}" from the menu? This can't be undone.`)) return;

  const saveStatusEl = document.getElementById('save-status');
  setStatus(saveStatusEl, 'Deleting...', false);
  try {
    const response = await staffFetch(`/api/menu/items/${encodeURIComponent(itemId)}`, { method: 'DELETE' });
    if (!response.ok) throw new Error(`Delete failed (${response.status}).`);
    window.location.href = '/edit.html';
  } catch (error) {
    setStatus(saveStatusEl, error.message, true);
  }
}

document.getElementById('add-modifier-btn').addEventListener('click', addModifier);
document.getElementById('add-choice-group-btn').addEventListener('click', addChoiceGroup);
document.getElementById('item-image-input').addEventListener('change', uploadItemImage);
document.getElementById('photo-google-btn').addEventListener('click', openGooglePhotoPicker);
document.getElementById('save-btn').addEventListener('click', saveItem);
document.getElementById('cancel-btn').addEventListener('click', () => { window.location.href = '/menu'; });
document.getElementById('delete-btn').addEventListener('click', deleteItem);

loadAdditionsCatalog();
loadItem();
