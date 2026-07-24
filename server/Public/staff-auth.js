async function staffFetch(url, options = {}) {
  const response = await fetch(url, options);
  if (response.status === 401) {
    window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
  }
  return response;
}
