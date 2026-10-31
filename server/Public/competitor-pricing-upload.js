function escapeHtmlQuickUpload(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// The restaurant a staff member picked via "Use My Location", if any — set
// once they tap a result, read by every photo uploaded afterward. Photos
// uploaded before this is set (or if it's never set at all) fall back to
// the plain review inbox, same as before this feature existed.
let selectedRestaurant = null; // { id, name }

// Every read-modify-write of the restaurants array (picking a restaurant,
// attaching a photo to one) goes through this chain so two uploads firing
// at once can't race each other's PUT and silently drop one photo's URL —
// each waits for the previous write to finish before reading its own copy.
let restaurantsWriteQueue = Promise.resolve();
function queueRestaurantsWrite(run) {
  const result = restaurantsWriteQueue.then(run);
  // Swallow so one failed write doesn't poison the queue for what comes after.
  restaurantsWriteQueue = result.catch(() => {});
  return result;
}

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

function geolocationErrorMessage(error) {
  switch (error.code) {
    case error.PERMISSION_DENIED:
      return "Location permission denied — you can still upload, it'll just go to the review inbox.";
    case error.POSITION_UNAVAILABLE:
      return 'Could not determine your location right now.';
    case error.TIMEOUT:
      return 'Location request timed out — try again.';
    default:
      return 'Could not get your location.';
  }
}

function renderGpsNearbyList(candidates) {
  const listEl = document.getElementById('gps-nearby-list');
  if (!candidates.length) {
    listEl.innerHTML = '<p class="hint">No restaurants found nearby — just upload and it\'ll go to the review inbox instead.</p>';
    return;
  }
  listEl.innerHTML = candidates
    .map(
      (c, i) => `
    <button type="button" class="secondary gps-candidate-btn" data-index="${i}">
      ${escapeHtmlQuickUpload(c.name)}
      <span class="hint">${c.distanceMiles} mi${c.address ? ' · ' + escapeHtmlQuickUpload(c.address) : ''}</span>
    </button>
  `
    )
    .join('');
  listEl.querySelectorAll('.gps-candidate-btn').forEach((btn) => {
    btn.addEventListener('click', () => selectCandidate(candidates[Number(btn.dataset.index)]));
  });
}

async function selectCandidate(candidate) {
  const statusEl = document.getElementById('selected-restaurant-status');
  statusEl.classList.remove('status-error', 'status-ok');
  statusEl.textContent = 'Saving…';
  try {
    const match = await queueRestaurantsWrite(async () => {
      const response = await staffFetch('/api/competitor-pricing/restaurants');
      const restaurants = response.ok ? await response.json() : [];
      const existing = restaurants.find((r) => r.placeId === candidate.placeId);
      if (existing) return existing;

      const created = {
        id: `restaurant-${Date.now()}`,
        name: candidate.name,
        distanceMiles: candidate.distanceMiles,
        address: candidate.address || null,
        website: null,
        notes: null,
        placeId: candidate.placeId,
        menuPhotoUrls: [],
      };
      restaurants.push(created);
      const saveResponse = await staffFetch('/api/competitor-pricing/restaurants', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(restaurants),
      });
      if (!saveResponse.ok) throw new Error(`Failed to save restaurant (${saveResponse.status}).`);
      return created;
    });

    selectedRestaurant = { id: match.id, name: match.name };
    statusEl.textContent = `Photos below will attach to: ${match.name} ✓`;
    statusEl.classList.add('status-ok');
    document.getElementById('gps-nearby-list').innerHTML = '';
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
}

document.getElementById('find-nearby-gps-btn').addEventListener('click', () => {
  const listEl = document.getElementById('gps-nearby-list');
  if (!navigator.geolocation) {
    listEl.innerHTML = '<p class="status status-error">Location isn\'t available in this browser.</p>';
    return;
  }
  listEl.innerHTML = '<p class="hint">Getting your location…</p>';
  navigator.geolocation.getCurrentPosition(
    async (position) => {
      listEl.innerHTML = '<p class="hint">Searching nearby…</p>';
      try {
        const { latitude, longitude } = position.coords;
        const response = await staffFetch(
          `/api/competitor-pricing/nearby-restaurants-by-location?lat=${latitude}&lng=${longitude}`
        );
        if (!response.ok) throw new Error(`Unable to search nearby restaurants (${response.status}).`);
        renderGpsNearbyList(await response.json());
      } catch (error) {
        listEl.innerHTML = `<p class="status status-error">${escapeHtmlQuickUpload(error.message)}</p>`;
      }
    },
    (error) => {
      listEl.innerHTML = `<p class="status status-error">${escapeHtmlQuickUpload(geolocationErrorMessage(error))}</p>`;
    },
    { enableHighAccuracy: true, timeout: 10000 }
  );
});

async function attachPhotoToSelectedRestaurant(url, restaurantId, restaurantName) {
  await queueRestaurantsWrite(async () => {
    const response = await staffFetch('/api/competitor-pricing/restaurants');
    const restaurants = response.ok ? await response.json() : [];
    const idx = restaurants.findIndex((r) => r.id === restaurantId);
    if (idx === -1) throw new Error(`${restaurantName} no longer exists — try picking it again.`);
    if (!restaurants[idx].menuPhotoUrls) restaurants[idx].menuPhotoUrls = [];
    restaurants[idx].menuPhotoUrls.push(url);
    const saveResponse = await staffFetch('/api/competitor-pricing/restaurants', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(restaurants),
    });
    if (!saveResponse.ok) throw new Error(`Failed to attach photo (${saveResponse.status}).`);
  });
}

async function uploadOnePhoto(file, row) {
  const statusEl = row.querySelector('.quick-upload-row-status');
  statusEl.textContent = 'Uploading…';
  // Captured at the start of this photo's own upload, not read again later —
  // if the staff member picks a restaurant partway through a batch, each
  // photo's fate is decided by what was selected when IT started uploading.
  const targetRestaurant = selectedRestaurant;

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();

    if (targetRestaurant) {
      await attachPhotoToSelectedRestaurant(result.url, targetRestaurant.id, targetRestaurant.name);
      statusEl.textContent = `Added to ${targetRestaurant.name} ✓`;
    } else {
      const inboxResponse = await staffFetch('/api/competitor-pricing/photos/inbox', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: result.url }),
      });
      if (!inboxResponse.ok) throw new Error(`Failed to queue for review (${inboxResponse.status}).`);
      statusEl.textContent = 'Added to review inbox ✓';
    }
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
