function escapeHtmlReviews(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function starString(rating) {
  const full = Math.round(rating);
  return '★'.repeat(full) + '☆'.repeat(Math.max(0, 5 - full));
}

async function loadReviewsWidget() {
  const el = document.getElementById('reviews-widget');
  if (!el) return;

  try {
    const response = await fetch('/api/place-reviews');
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (!data.reviews || !data.reviews.length) {
      el.hidden = true;
      return;
    }

    el.hidden = false;
    el.innerHTML = data.reviews
      .map(
        (r) => `
      <div class="review-card">
        <div class="review-card-header">
          ${r.profilePhotoUrl ? `<img class="review-avatar" src="${escapeHtmlReviews(r.profilePhotoUrl)}" alt="" />` : ''}
          <div>
            <div class="review-author">${escapeHtmlReviews(r.authorName)}</div>
            <div class="review-stars" aria-label="${r.rating} out of 5 stars">${starString(r.rating)}</div>
          </div>
        </div>
        <p class="review-text">${escapeHtmlReviews(r.text)}</p>
        <p class="review-source">${escapeHtmlReviews(r.relativeTime)} &middot; via Google</p>
      </div>
    `
      )
      .join('');
  } catch {
    el.hidden = true;
  }
}

loadReviewsWidget();
