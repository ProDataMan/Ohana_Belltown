function escapeHtmlEntertainmentNight(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// Static per-night copy — matches the weekly schedule table on /entertainment.
// Purely presentation; which bookings actually show up on each page comes
// from the server (a booking's date determines its night, not this config).
const NIGHT_CONFIG = {
  monday: {
    title: 'No Entertainment',
    eyebrow: 'Mondays',
    tagline: '',
    description: "Nothing scheduled on Mondays right now — we're still open, just no live entertainment that night.",
    emptyMessage: 'Nothing booked for Monday right now — check back, or see the full weekly lineup.',
  },
  tuesday: {
    title: 'No Entertainment',
    eyebrow: 'Tuesdays',
    tagline: '',
    description: "Nothing scheduled on Tuesdays right now — we're still open, just no live entertainment that night.",
    emptyMessage: 'Nothing booked for Tuesday right now — check back, or see the full weekly lineup.',
  },
  wednesday: {
    title: 'Island Nights',
    eyebrow: 'Wednesdays, 9pm',
    tagline: 'Free live island music every Wednesday.',
    description: 'Grab a table, order a tropical drink, and soak in the aloha.',
    emptyMessage: "This Wednesday's performer hasn't been posted yet — follow us on Facebook/Instagram or check back soon.",
  },
  thursday: {
    title: 'DJ Night',
    eyebrow: 'Thursdays',
    tagline: "Seattle's best DJs.",
    description: 'A rotating lineup of Seattle DJs — follow us on Facebook/Instagram for who\'s spinning this week.',
    emptyMessage: "This Thursday's DJ hasn't been posted yet — follow us on Facebook/Instagram or check back soon.",
  },
  friday: {
    title: 'DJ Night',
    eyebrow: 'Fridays',
    tagline: "Seattle's best DJs.",
    description: 'A rotating lineup of Seattle DJs — follow us on Facebook/Instagram for who\'s spinning this week.',
    emptyMessage: "This Friday's DJ hasn't been posted yet — follow us on Facebook/Instagram or check back soon.",
  },
  saturday: {
    title: 'DJ Night',
    eyebrow: 'Saturdays',
    tagline: "Seattle's best DJs.",
    description: 'A rotating lineup of Seattle DJs — follow us on Facebook/Instagram for who\'s spinning this week.',
    emptyMessage: "This Saturday's DJ hasn't been posted yet — follow us on Facebook/Instagram or check back soon.",
  },
  sunday: {
    title: 'Karaoke',
    eyebrow: 'Sundays',
    tagline: 'Grab the mic.',
    description: "Karaoke every Sunday — sign up with the KJ when you arrive and take your turn on the mic.",
    emptyMessage: "This Sunday's karaoke host hasn't been posted yet — follow us on Facebook/Instagram or check back soon.",
  },
};

function formatNightDate(dateStr) {
  const [year, month, day] = dateStr.split('-').map(Number);
  if (!year) return dateStr;
  return new Date(year, month - 1, day).toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

function formatNightTime(timeStr) {
  if (!timeStr) return null;
  const [hours, minutes] = timeStr.split(':').map(Number);
  if (Number.isNaN(hours)) return null;
  return new Date(2000, 0, 1, hours, minutes).toLocaleTimeString(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  });
}

function capitalize(word) {
  return word.charAt(0).toUpperCase() + word.slice(1);
}

async function initEntertainmentNightPage() {
  const weekday = window.location.pathname.split('/').filter(Boolean).pop();
  const config = NIGHT_CONFIG[weekday];
  if (!config) return; // server already 404s an unknown weekday before this loads

  const dayName = capitalize(weekday);
  const pageTitle = `${config.title} — ${dayName} | Ohana Belltown`;
  const description = `${config.title} at Ohana Belltown every ${dayName}. ${config.description}`;

  document.getElementById('night-title').textContent = pageTitle;
  document.getElementById('meta-description').setAttribute('content', description);
  document.getElementById('meta-og-title').setAttribute('content', pageTitle);
  document.getElementById('meta-og-description').setAttribute('content', description);
  document.getElementById('meta-og-url').setAttribute('content', `https://www.ohanasushigrill.com/entertainment/${weekday}`);
  document.getElementById('canonical-link').setAttribute('href', `https://www.ohanasushigrill.com/entertainment/${weekday}`);

  document.getElementById('night-eyebrow').textContent = config.eyebrow;
  document.getElementById('night-heading').textContent = config.title;
  document.getElementById('night-tagline').textContent = config.tagline;
  document.getElementById('night-description').textContent = config.description;

  const bookingsSection = document.getElementById('night-bookings-section');
  const bookingsList = document.getElementById('night-bookings-list');
  const emptySection = document.getElementById('night-empty-section');
  const emptyMessage = document.getElementById('night-empty-message');

  try {
    const response = await fetch(`/api/entertainment/upcoming?weekday=${weekday}`);
    if (!response.ok) throw new Error();
    const bookings = await response.json();

    if (!bookings.length) {
      emptyMessage.textContent = config.emptyMessage;
      emptySection.hidden = false;
      return;
    }

    bookingsList.innerHTML = bookings
      .map(
        (b) => `
      <div class="performer-card">
        <p class="eyebrow">${escapeHtmlEntertainmentNight(formatNightDate(b.date))}${formatNightTime(b.startTime) ? ' &middot; ' + escapeHtmlEntertainmentNight(formatNightTime(b.startTime)) : ''}</p>
        <h3>${escapeHtmlEntertainmentNight(b.performerName)}</h3>
        ${b.bio ? `<p>${escapeHtmlEntertainmentNight(b.bio)}</p>` : ''}
        ${
          (b.photos || []).length
            ? `<div class="performer-photos">
                 ${b.photos
                   .map(
                     (url) => `
                   <button type="button" class="gallery-item" data-src="${escapeHtmlEntertainmentNight(url)}" data-caption="${escapeHtmlEntertainmentNight(b.performerName)}">
                     <img src="${escapeHtmlEntertainmentNight(url)}" alt="${escapeHtmlEntertainmentNight(b.performerName)}" loading="lazy" />
                   </button>
                 `
                   )
                   .join('')}
               </div>`
            : ''
        }
        ${b.videoURL ? `<video controls preload="metadata" src="${escapeHtmlEntertainmentNight(b.videoURL)}"></video>` : ''}
      </div>
    `
      )
      .join('');

    bookingsList.querySelectorAll('.gallery-item').forEach((el) => {
      el.addEventListener('click', () => {
        window.openLightbox(el.dataset.src, el.dataset.caption);
      });
    });

    bookingsSection.hidden = false;
  } catch {
    emptyMessage.textContent = config.emptyMessage;
    emptySection.hidden = false;
  }
}

initEntertainmentNightPage();
