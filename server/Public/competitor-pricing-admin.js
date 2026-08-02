function escapeHtmlCompetitor(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function todayDateInputValue() {
  return new Date().toISOString().slice(0, 10);
}

let menuItems = [];
let groups = [];
let restaurants = [];
let entries = [];
let aiExtractionAvailable = false;

function restaurantName(id) {
  return restaurants.find((r) => r.id === id)?.name || '(removed restaurant)';
}

function groupLabel(id) {
  return groups.find((g) => g.id === id)?.label || '(removed group)';
}

function menuItemOptionsHtml(selectedId) {
  return (
    '<option value="">Not linked to one of our items</option>' +
    menuItems
      .map(
        (item) =>
          `<option value="${item.id}" ${item.id === selectedId ? 'selected' : ''}>${escapeHtmlCompetitor(item.name)}${item.price != null ? ` ($${Number(item.price).toFixed(2)})` : ''}</option>`
      )
      .join('')
  );
}

async function loadMenuItems() {
  try {
    const response = await fetch('/api/menu');
    if (!response.ok) return;
    const data = await response.json();
    menuItems = (data.categories || []).flatMap((c) => c.items || []).map((item) => ({ id: item.id, name: item.name, price: item.price }));
    document.getElementById('new-group-item-select').innerHTML = menuItemOptionsHtml(null);
  } catch {
    // the group form still works without linking to one of our items
  }
}

// ---- Price Comparison Report (read-only) ----

async function loadReport() {
  const listEl = document.getElementById('report-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/competitor-pricing/report');
    if (!response.ok) throw new Error(`Unable to load the report (${response.status}).`);
    const rows = await response.json();

    if (!rows.length) {
      listEl.innerHTML = '<p class="hint">No comparison groups yet — add one below, then add competitor price entries for it.</p>';
      return;
    }

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Comparison</th><th>Vs. Average</th><th>Our Price</th><th>Competitor Avg</th><th>Range</th><th>Details</th></tr></thead>
          <tbody>
            ${rows
              .map((row) => {
                const ourPriceText = row.ourPrice != null ? `$${row.ourPrice.toFixed(2)}` : row.ourMenuItemId ? '<span class="hint">item not found</span>' : '<span class="hint">not linked</span>';
                const avgText = row.competitorAverage != null ? `$${row.competitorAverage.toFixed(2)} (${row.competitorCount})` : '<span class="hint">no data yet</span>';
                const rangeText = row.competitorMin != null ? `$${row.competitorMin.toFixed(2)}&ndash;$${row.competitorMax.toFixed(2)}` : '';
                let deltaText = '<span class="hint">&mdash;</span>';
                if (row.deltaVsAverage != null) {
                  const pct = row.deltaPercentVsAverage;
                  const sign = row.deltaVsAverage > 0 ? '+' : '';
                  const pillClass = row.deltaVsAverage > 0 ? 'pill-denied' : 'pill-approved';
                  deltaText = `<span class="pill ${pillClass}">${sign}$${row.deltaVsAverage.toFixed(2)} (${sign}${pct.toFixed(0)}%)</span>`;
                }
                const entriesDetail = row.entries.length
                  ? `<details><summary>${row.entries.length} price${row.entries.length === 1 ? '' : 's'}</summary>
                      <ul class="plain-list">
                        ${row.entries
                          .map(
                            (e) => `
                          <li>
                            ${escapeHtmlCompetitor(e.restaurantName)}${e.distanceMiles != null ? ` (${e.distanceMiles} mi)` : ''}
                            &mdash; $${e.price.toFixed(2)}${e.itemName ? ` &ldquo;${escapeHtmlCompetitor(e.itemName)}&rdquo;` : ''}
                            ${e.sourceURL ? ` &mdash; <a href="${escapeHtmlCompetitor(e.sourceURL)}" target="_blank" rel="noopener">source</a>` : ''}
                            <span class="hint">(checked ${escapeHtmlCompetitor(e.checkedAt)})</span>
                          </li>
                        `
                          )
                          .join('')}
                      </ul>
                    </details>`
                  : '<span class="hint">no entries yet</span>';
                return `
                <tr>
                  <td>${escapeHtmlCompetitor(row.label)}${row.ourMenuItemName ? `<div class="hint">${escapeHtmlCompetitor(row.ourMenuItemName)}</div>` : ''}</td>
                  <td>${deltaText}</td>
                  <td>${ourPriceText}</td>
                  <td>${avgText}</td>
                  <td>${rangeText}</td>
                  <td>${entriesDetail}</td>
                </tr>
              `;
              })
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlCompetitor(error.message)}</p>`;
  }
}

document.getElementById('reload-report-btn').addEventListener('click', loadReport);

// ---- Comparison Groups ----

function renderGroupsList() {
  const listEl = document.getElementById('groups-list');
  if (!groups.length) {
    listEl.innerHTML = '<p class="hint">No comparison groups yet — add one below.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Comparison Name</th><th>Linked Item</th><th>Notes</th><th></th></tr></thead>
        <tbody>
          ${groups
            .map(
              (g, i) => `
            <tr data-index="${i}">
              <td><input type="text" class="group-label-input" value="${escapeHtmlCompetitor(g.label)}" /></td>
              <td><select class="group-item-select">${menuItemOptionsHtml(g.ourMenuItemId)}</select></td>
              <td><input type="text" class="group-notes-input" value="${escapeHtmlCompetitor(g.notes || '')}" /></td>
              <td><button type="button" class="secondary group-remove-btn">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.group-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const index = Number(btn.closest('tr').dataset.index);
      groups.splice(index, 1);
      renderGroupsList();
    });
  });
}

async function loadGroups() {
  try {
    const response = await staffFetch('/api/competitor-pricing/groups');
    if (!response.ok) throw new Error(`Unable to load comparison groups (${response.status}).`);
    groups = await response.json();
    renderGroupsList();
    refreshEntryFormSelects();
  } catch (error) {
    document.getElementById('groups-list').innerHTML = `<p class="status status-error">${escapeHtmlCompetitor(error.message)}</p>`;
  }
}

document.getElementById('reload-groups-btn').addEventListener('click', loadGroups);

document.getElementById('groups-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const labelInput = document.getElementById('new-group-label-input');
  const itemSelect = document.getElementById('new-group-item-select');
  const label = labelInput.value.trim();
  if (!label) return;
  groups.push({ id: `group-${Date.now()}`, label, ourMenuItemId: itemSelect.value || null, notes: null });
  labelInput.value = '';
  itemSelect.value = '';
  renderGroupsList();
  refreshEntryFormSelects();
});

// Reads whatever's currently typed into each group row's inputs — used both
// by the Save button and by the AI-extraction flow, which needs to append a
// brand-new group without clobbering any not-yet-saved edits to existing ones.
function currentGroupsFromDOM() {
  const rows = document.querySelectorAll('#groups-list tr[data-index]');
  return Array.from(rows).map((row, i) => ({
    id: groups[i].id,
    label: row.querySelector('.group-label-input').value.trim(),
    ourMenuItemId: row.querySelector('.group-item-select').value || null,
    notes: row.querySelector('.group-notes-input').value.trim() || null,
  }));
}

document.getElementById('save-groups-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('groups-status');
  const updated = currentGroupsFromDOM();
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/competitor-pricing/groups', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updated),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    groups = await response.json();
    renderGroupsList();
    refreshEntryFormSelects();
    statusEl.textContent = 'Groups saved!';
    statusEl.classList.add('status-ok');
    await loadReport();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

// ---- Competitor Restaurants ----

// Reads whatever's currently typed into each row's inputs back into the
// `restaurants` array before a photo upload/remove triggers a re-render —
// otherwise an in-progress, not-yet-saved text edit would be silently
// wiped out when the table rebuilds from stale in-memory data.
function syncRestaurantsFromDOM() {
  document.querySelectorAll('#restaurants-list tr[data-index]').forEach((row, i) => {
    if (!restaurants[i]) return;
    restaurants[i].name = row.querySelector('.restaurant-name-input').value.trim();
    const distanceRaw = row.querySelector('.restaurant-distance-input').value;
    restaurants[i].distanceMiles = distanceRaw ? Number(distanceRaw) : null;
    restaurants[i].address = row.querySelector('.restaurant-address-input').value.trim() || null;
    restaurants[i].website = row.querySelector('.restaurant-website-input').value.trim() || null;
    restaurants[i].notes = row.querySelector('.restaurant-notes-input').value.trim() || null;
  });
}

function renderRestaurantsList() {
  const listEl = document.getElementById('restaurants-list');
  if (!restaurants.length) {
    listEl.innerHTML = '<p class="hint">No competitor restaurants yet — find some nearby below.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Name</th><th>Miles</th><th>Address</th><th>Website</th><th>Notes</th><th>Menu Photos</th><th></th></tr></thead>
        <tbody>
          ${restaurants
            .map(
              (r, i) => `
            <tr data-index="${i}">
              <td><input type="text" class="restaurant-name-input" value="${escapeHtmlCompetitor(r.name)}" /></td>
              <td><input type="number" min="0" step="0.1" class="restaurant-distance-input" value="${r.distanceMiles ?? ''}" style="max-width: 6rem;" /></td>
              <td><input type="text" class="restaurant-address-input" value="${escapeHtmlCompetitor(r.address || '')}" /></td>
              <td><input type="text" class="restaurant-website-input" value="${escapeHtmlCompetitor(r.website || '')}" /></td>
              <td><input type="text" class="restaurant-notes-input" value="${escapeHtmlCompetitor(r.notes || '')}" /></td>
              <td>
                <div class="item-thumb-gallery">
                  ${(r.menuPhotoUrls || [])
                    .map(
                      (url, photoIndex) => `
                    <div class="menu-photo-item">
                      <div class="item-thumb-wrap">
                        <a href="${escapeHtmlCompetitor(url)}" target="_blank" rel="noopener">
                          <img class="item-thumb" src="${escapeHtmlCompetitor(url)}" alt="Menu photo" />
                        </a>
                        <button type="button" class="thumb-remove-btn menu-photo-remove-btn" data-photo-index="${photoIndex}" aria-label="Remove this menu photo">&times;</button>
                      </div>
                      ${
                        aiExtractionAvailable
                          ? `<button type="button" class="secondary menu-photo-extract-btn" data-photo-url="${escapeHtmlCompetitor(url)}">Extract Items</button>`
                          : ''
                      }
                    </div>
                  `
                    )
                    .join('')}
                </div>
                <label class="photo-upload-btn">
                  + Add Photo
                  <input type="file" accept="image/*" class="menu-photo-upload-input" hidden />
                </label>
                <p class="hint menu-photo-status"></p>
              </td>
              <td><button type="button" class="secondary restaurant-remove-btn">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.restaurant-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      syncRestaurantsFromDOM();
      const index = Number(btn.closest('tr').dataset.index);
      restaurants.splice(index, 1);
      renderRestaurantsList();
    });
  });
  listEl.querySelectorAll('.menu-photo-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      syncRestaurantsFromDOM();
      const restaurantIndex = Number(btn.closest('tr').dataset.index);
      const photoIndex = Number(btn.dataset.photoIndex);
      restaurants[restaurantIndex].menuPhotoUrls.splice(photoIndex, 1);
      renderRestaurantsList();
    });
  });
  listEl.querySelectorAll('.menu-photo-upload-input').forEach((input) => {
    input.addEventListener('change', (event) => uploadMenuPhoto(event, Number(input.closest('tr').dataset.index)));
  });
  listEl.querySelectorAll('.menu-photo-extract-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const restaurantIndex = Number(btn.closest('tr').dataset.index);
      extractMenuItems(btn.dataset.photoUrl, restaurantIndex, btn);
    });
  });
}

async function uploadMenuPhoto(event, restaurantIndex) {
  const file = event.target.files[0];
  if (!file) return;
  const statusEl = event.target.closest('td').querySelector('.menu-photo-status');
  statusEl.textContent = 'Uploading...';
  statusEl.classList.remove('status-error');

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();
    syncRestaurantsFromDOM();
    if (!restaurants[restaurantIndex].menuPhotoUrls) restaurants[restaurantIndex].menuPhotoUrls = [];
    restaurants[restaurantIndex].menuPhotoUrls.push(result.url);
    renderRestaurantsList();
    document.getElementById('restaurants-status').textContent = 'Photo added — click Save Restaurants to keep it.';
    document.getElementById('restaurants-status').classList.remove('status-error', 'status-ok');
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
}

// ---- AI menu extraction (gated on ANTHROPIC_API_KEY being configured) ----

async function loadAIExtractionStatus() {
  try {
    const response = await staffFetch('/api/competitor-pricing/ai-extraction-status');
    if (!response.ok) return;
    const status = await response.json();
    aiExtractionAvailable = status.available;
  } catch {
    aiExtractionAvailable = false;
  }
}

async function extractMenuItems(photoUrl, restaurantIndex, btn) {
  const originalText = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'Reading...';
  try {
    const response = await staffFetch('/api/competitor-pricing/extract-menu', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ photoUrl }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Extraction failed (${response.status}).`);
    }
    const result = await response.json();
    renderExtractionResults(result.items, restaurantIndex, photoUrl);
  } catch (error) {
    alert(error.message);
  } finally {
    btn.disabled = false;
    btn.textContent = originalText;
  }
}

function renderExtractionResults(items, restaurantIndex, photoUrl) {
  const panel = document.getElementById('ai-extraction-panel');
  const listEl = document.getElementById('ai-extraction-list');
  const restaurant = restaurants[restaurantIndex];
  panel.hidden = false;

  if (!items.length) {
    listEl.innerHTML = `<p class="hint">No items could be read from that photo of ${escapeHtmlCompetitor(restaurant.name)}'s menu.</p>`;
    return;
  }

  listEl.innerHTML = `
    <p class="hint">From ${escapeHtmlCompetitor(restaurant.name)}'s menu photo — review each before adding:</p>
    <div class="data-table">
      <table>
        <thead><tr><th>Name</th><th>Price</th><th>Compare To</th><th></th></tr></thead>
        <tbody>
          ${items
            .map(
              (item, i) => `
            <tr data-index="${i}">
              <td><input type="text" class="extracted-name-input" value="${escapeHtmlCompetitor(item.name)}" /></td>
              <td><input type="number" min="0" step="0.01" class="extracted-price-input" value="${item.price ?? ''}" style="max-width: 6rem;" /></td>
              <td>
                <select class="extracted-group-select">
                  <option value="__new__">+ New comparison group</option>
                  ${groups.map((g) => `<option value="${g.id}">${escapeHtmlCompetitor(g.label)}</option>`).join('')}
                </select>
              </td>
              <td><button type="button" class="secondary extracted-add-btn">Add as Price Entry</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;

  listEl.querySelectorAll('.extracted-add-btn').forEach((btn) => {
    btn.addEventListener('click', () => addExtractedItemAsEntry(btn, restaurantIndex, photoUrl));
  });
}

async function addExtractedItemAsEntry(btn, restaurantIndex, photoUrl) {
  const row = btn.closest('tr');
  const name = row.querySelector('.extracted-name-input').value.trim();
  const priceRaw = row.querySelector('.extracted-price-input').value;
  const groupSelect = row.querySelector('.extracted-group-select');
  if (!name || !priceRaw) return alert('Enter both a name and a price first.');

  btn.disabled = true;
  btn.textContent = 'Adding...';

  try {
    // Make sure the restaurant this photo belongs to actually exists
    // server-side before pointing an entry at it — it may have only been
    // added via the Nearby Search picker moments ago and never explicitly
    // saved.
    const restaurantsResponse = await staffFetch('/api/competitor-pricing/restaurants', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(currentRestaurantsFromDOM()),
    });
    if (!restaurantsResponse.ok) throw new Error(`Failed to save the restaurant (${restaurantsResponse.status}).`);
    restaurants = await restaurantsResponse.json();
    renderRestaurantsList();

    let groupId = groupSelect.value;
    if (groupId === '__new__') {
      const newGroup = { id: `group-${Date.now()}`, label: name, ourMenuItemId: null, notes: null };
      const groupsResponse = await staffFetch('/api/competitor-pricing/groups', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify([...currentGroupsFromDOM(), newGroup]),
      });
      if (!groupsResponse.ok) throw new Error(`Failed to create the comparison group (${groupsResponse.status}).`);
      groups = await groupsResponse.json();
      renderGroupsList();
      refreshEntryFormSelects();
      groupId = newGroup.id;
    }

    const restaurant = restaurants[restaurantIndex];
    const newEntry = {
      id: `entry-${Date.now()}`,
      groupId,
      restaurantId: restaurant.id,
      price: Number(priceRaw),
      itemName: name,
      sourceURL: photoUrl,
      checkedAt: todayDateInputValue(),
    };
    const entriesResponse = await staffFetch('/api/competitor-pricing/entries', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify([...currentEntriesFromDOM(), newEntry]),
    });
    if (!entriesResponse.ok) throw new Error(`Failed to save the price entry (${entriesResponse.status}).`);
    entries = await entriesResponse.json();
    renderEntriesList();
    refreshEntryFormSelects();
    await loadReport();

    btn.textContent = 'Added ✓';
  } catch (error) {
    alert(error.message);
    btn.disabled = false;
    btn.textContent = 'Add as Price Entry';
  }
}

async function loadRestaurants() {
  try {
    const response = await staffFetch('/api/competitor-pricing/restaurants');
    if (!response.ok) throw new Error(`Unable to load competitor restaurants (${response.status}).`);
    restaurants = await response.json();
    renderRestaurantsList();
    refreshEntryFormSelects();
  } catch (error) {
    document.getElementById('restaurants-list').innerHTML = `<p class="status status-error">${escapeHtmlCompetitor(error.message)}</p>`;
  }
}

document.getElementById('reload-restaurants-btn').addEventListener('click', loadRestaurants);

// ---- Find Nearby Restaurants (Google Maps) ----

function renderNearbyList(candidates) {
  const listEl = document.getElementById('nearby-list');
  if (!candidates.length) {
    listEl.innerHTML = '<p class="hint">No results — try a larger radius, or Google Maps credentials aren\'t configured yet.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Name</th><th>Distance</th><th>Address</th><th>Rating</th><th></th></tr></thead>
        <tbody>
          ${candidates
            .map((c) => {
              const alreadyAdded = restaurants.some((r) => r.placeId === c.placeId);
              return `
              <tr data-place-id="${escapeHtmlCompetitor(c.placeId)}">
                <td>${escapeHtmlCompetitor(c.name)}</td>
                <td>${c.distanceMiles} mi</td>
                <td>${escapeHtmlCompetitor(c.address || '')}</td>
                <td>${c.rating != null ? `&#9733; ${c.rating}` : ''}</td>
                <td><button type="button" class="secondary nearby-add-btn" ${alreadyAdded ? 'disabled' : ''}>${alreadyAdded ? 'Added' : 'Add'}</button></td>
              </tr>
            `;
            })
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.nearby-add-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const placeId = btn.closest('tr').dataset.placeId;
      const candidate = candidates.find((c) => c.placeId === placeId);
      if (!candidate) return;
      restaurants.push({
        id: `restaurant-${Date.now()}`,
        name: candidate.name,
        distanceMiles: candidate.distanceMiles,
        address: candidate.address || null,
        website: null,
        notes: null,
        placeId: candidate.placeId,
      });
      renderRestaurantsList();
      refreshEntryFormSelects();
      btn.disabled = true;
      btn.textContent = 'Added';
    });
  });
}

document.getElementById('find-nearby-btn').addEventListener('click', async () => {
  const listEl = document.getElementById('nearby-list');
  const radius = document.getElementById('nearby-radius-input').value || 3;
  listEl.innerHTML = '<p class="hint">Searching Google Maps...</p>';
  try {
    const response = await staffFetch(`/api/competitor-pricing/nearby-restaurants?radiusMiles=${encodeURIComponent(radius)}`);
    if (!response.ok) throw new Error(`Unable to search nearby restaurants (${response.status}).`);
    const candidates = await response.json();
    renderNearbyList(candidates);
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlCompetitor(error.message)}</p>`;
  }
});

// Same idea as currentGroupsFromDOM()/currentEntriesFromDOM() — also used
// by the AI-extraction flow, which needs the restaurant it's attaching a
// price entry to to actually exist server-side first (a restaurant added
// via the Nearby Search picker but not yet explicitly saved otherwise
// leaves that entry referencing a restaurant nothing else knows about, so
// it silently doesn't show up in the report).
function currentRestaurantsFromDOM() {
  const rows = document.querySelectorAll('#restaurants-list tr[data-index]');
  return Array.from(rows).map((row, i) => {
    const distanceRaw = row.querySelector('.restaurant-distance-input').value;
    return {
      id: restaurants[i].id,
      name: row.querySelector('.restaurant-name-input').value.trim(),
      distanceMiles: distanceRaw ? Number(distanceRaw) : null,
      address: row.querySelector('.restaurant-address-input').value.trim() || null,
      website: row.querySelector('.restaurant-website-input').value.trim() || null,
      notes: row.querySelector('.restaurant-notes-input').value.trim() || null,
      placeId: restaurants[i].placeId || null,
      menuPhotoUrls: restaurants[i].menuPhotoUrls || null,
    };
  });
}

document.getElementById('save-restaurants-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('restaurants-status');
  const updated = currentRestaurantsFromDOM();
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/competitor-pricing/restaurants', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updated),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    restaurants = await response.json();
    renderRestaurantsList();
    refreshEntryFormSelects();
    statusEl.textContent = 'Restaurants saved!';
    statusEl.classList.add('status-ok');
    await loadReport();
    await loadEntries();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

// ---- Price Entries ----

function refreshEntryFormSelects() {
  const groupSelect = document.getElementById('new-entry-group-select');
  const restaurantSelect = document.getElementById('new-entry-restaurant-select');
  groupSelect.innerHTML = groups.map((g) => `<option value="${g.id}">${escapeHtmlCompetitor(g.label)}</option>`).join('');
  restaurantSelect.innerHTML = restaurants.map((r) => `<option value="${r.id}">${escapeHtmlCompetitor(r.name)}</option>`).join('');
}

function renderEntriesList() {
  const listEl = document.getElementById('entries-list');
  if (!entries.length) {
    listEl.innerHTML = '<p class="hint">No price entries yet — add one below.</p>';
    return;
  }
  const groupOptions = (selectedId) => groups.map((g) => `<option value="${g.id}" ${g.id === selectedId ? 'selected' : ''}>${escapeHtmlCompetitor(g.label)}</option>`).join('');
  const restaurantOptions = (selectedId) =>
    restaurants.map((r) => `<option value="${r.id}" ${r.id === selectedId ? 'selected' : ''}>${escapeHtmlCompetitor(r.name)}</option>`).join('');

  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Comparison</th><th>Restaurant</th><th>Their Price</th><th>Their Item Name</th><th>Source</th><th>Checked</th><th></th></tr></thead>
        <tbody>
          ${entries
            .map(
              (e, i) => `
            <tr data-index="${i}">
              <td><select class="entry-group-select">${groupOptions(e.groupId)}</select></td>
              <td><select class="entry-restaurant-select">${restaurantOptions(e.restaurantId)}</select></td>
              <td><input type="number" min="0" step="0.01" class="entry-price-input" value="${e.price}" style="max-width: 6rem;" /></td>
              <td><input type="text" class="entry-item-name-input" value="${escapeHtmlCompetitor(e.itemName || '')}" /></td>
              <td><input type="text" class="entry-source-input" value="${escapeHtmlCompetitor(e.sourceURL || '')}" placeholder="https://..." /></td>
              <td><input type="date" class="entry-checked-input" value="${escapeHtmlCompetitor(e.checkedAt)}" /></td>
              <td><button type="button" class="secondary entry-remove-btn">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.entry-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const index = Number(btn.closest('tr').dataset.index);
      entries.splice(index, 1);
      renderEntriesList();
    });
  });
}

async function loadEntries() {
  try {
    const response = await staffFetch('/api/competitor-pricing/entries');
    if (!response.ok) throw new Error(`Unable to load price entries (${response.status}).`);
    entries = await response.json();
    renderEntriesList();
  } catch (error) {
    document.getElementById('entries-list').innerHTML = `<p class="status status-error">${escapeHtmlCompetitor(error.message)}</p>`;
  }
}

document.getElementById('reload-entries-btn').addEventListener('click', loadEntries);

document.getElementById('entries-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const groupSelect = document.getElementById('new-entry-group-select');
  const restaurantSelect = document.getElementById('new-entry-restaurant-select');
  const priceInput = document.getElementById('new-entry-price-input');
  if (!groupSelect.value || !restaurantSelect.value || !priceInput.value) return;
  entries.push({
    id: `entry-${Date.now()}`,
    groupId: groupSelect.value,
    restaurantId: restaurantSelect.value,
    price: Number(priceInput.value),
    itemName: null,
    sourceURL: null,
    checkedAt: todayDateInputValue(),
  });
  priceInput.value = '';
  renderEntriesList();
});

// Same idea as currentGroupsFromDOM() — reused by the AI-extraction flow so
// adding one new entry can't silently drop an unsaved edit to another row.
function currentEntriesFromDOM() {
  const rows = document.querySelectorAll('#entries-list tr[data-index]');
  return Array.from(rows).map((row, i) => ({
    id: entries[i].id,
    groupId: row.querySelector('.entry-group-select').value,
    restaurantId: row.querySelector('.entry-restaurant-select').value,
    price: Number(row.querySelector('.entry-price-input').value),
    itemName: row.querySelector('.entry-item-name-input').value.trim() || null,
    sourceURL: row.querySelector('.entry-source-input').value.trim() || null,
    checkedAt: row.querySelector('.entry-checked-input').value || todayDateInputValue(),
  }));
}

document.getElementById('save-entries-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('entries-status');
  const updated = currentEntriesFromDOM();
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/competitor-pricing/entries', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updated),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    entries = await response.json();
    renderEntriesList();
    statusEl.textContent = 'Entries saved!';
    statusEl.classList.add('status-ok');
    await loadReport();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

(async () => {
  await loadMenuItems();
  await loadAIExtractionStatus();
  await loadRestaurants();
  await loadGroups();
  await loadEntries();
  await loadReport();
})();
