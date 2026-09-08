// A compact star-rating + review-count line for the top of the Menu page —
// deliberately not the full review-card carousel the homepage uses (see
// reviews-widget.js), since a guest here is about to order, not browse
// testimonials. Best-effort: silently stays hidden if Google Places isn't
// configured or returns no rating.
function starStringMenuSummary(rating) {
  const full = Math.round(rating);
  return '★'.repeat(full) + '☆'.repeat(Math.max(0, 5 - full));
}

async function loadMenuReviewSummary() {
  const el = document.getElementById('menu-review-summary');
  if (!el) return;
  try {
    const response = await fetch('/api/place-reviews');
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (!data.overallRating || !data.totalRatings) return;

    const stars = el.querySelector('.review-stars');
    stars.textContent = starStringMenuSummary(data.overallRating);
    stars.setAttribute('aria-label', `${data.overallRating} out of 5 stars`);
    document.getElementById('menu-review-count').textContent =
      `${data.overallRating.toFixed(1)} (${data.totalRatings} Google reviews)`;
    el.hidden = false;
  } catch {
    // Stays hidden — see file header.
  }
}

loadMenuReviewSummary();
