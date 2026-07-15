function getStaffPin() {
  let pin = localStorage.getItem('ohanaStaffPin');
  if (!pin) {
    pin = window.prompt('Enter the staff PIN for this action:');
    if (pin) localStorage.setItem('ohanaStaffPin', pin.trim());
  }
  return (pin || '').trim();
}

function clearStaffPin() {
  localStorage.removeItem('ohanaStaffPin');
}

async function staffFetch(url, options = {}) {
  const pin = getStaffPin();
  const headers = Object.assign({}, options.headers, { 'X-Staff-Pin': pin });
  const response = await fetch(url, Object.assign({}, options, { headers }));
  if (response.status === 401) {
    clearStaffPin();
  }
  return response;
}
