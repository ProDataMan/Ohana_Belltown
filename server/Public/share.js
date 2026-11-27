// Sharing a dish, deal, or event: the phone's share sheet (Messages,
// Instagram, Facebook…) where there is one, otherwise copy the link. Shared
// links are tagged utm_source=share so Analytics shows visits from shares,
// and each share is counted as a "share" action.
(() => {
  function taggedUrl(url, campaign) {
    const u = new URL(url, window.location.origin);
    u.searchParams.set('utm_source', 'share');
    if (campaign) u.searchParams.set('utm_campaign', campaign);
    return u.toString();
  }

  function countShare() { window.ohanaCountAction('share'); }

  /// Counts a guest action ("share", "add-to-calendar", "review") on Analytics.
  window.ohanaCountAction = function ohanaCountAction(action) {
    const payload = JSON.stringify({ action, page: window.location.pathname, source: (() => { try { return sessionStorage.getItem('ohana_visit_source') || 'unknown'; } catch { return 'unknown'; } })() });
    if (navigator.sendBeacon) navigator.sendBeacon('/api/analytics/action', new Blob([payload], { type: 'application/json' }));
  };

  /// Shares `url` (tagged) with `title`; resolves to "shared", "copied", or
  /// "cancelled". `button`, if given, briefly says "Link copied!".
  window.ohanaShare = async function ohanaShare({ title, text, url, campaign, button }) {
    const link = taggedUrl(url, campaign);
    if (navigator.share) {
      try {
        await navigator.share({ title, text, url: link });
        countShare();
        return 'shared';
      } catch {
        return 'cancelled';
      }
    }
    try {
      await navigator.clipboard.writeText(link);
      countShare();
      if (button) {
        const label = button.textContent;
        button.textContent = 'Link copied!';
        setTimeout(() => { button.textContent = label; }, 2000);
      }
      return 'copied';
    } catch {
      window.prompt('Copy this link:', link);
      return 'copied';
    }
  };

  // Any button with .share-this-btn shares the page it's on.
  document.querySelectorAll('.share-this-btn').forEach((button) => {
    button.addEventListener('click', () => {
      const canonical = document.querySelector('link[rel="canonical"]')?.href || window.location.href;
      window.ohanaShare({ title: button.dataset.title || document.title, url: canonical, campaign: window.location.pathname.split('/').filter(Boolean).join('-'), button });
    });
  });
})();
