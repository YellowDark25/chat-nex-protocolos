const API_ROOT = '/chamados-api';

function accountIdFromPath() {
  const fromQuery = new URLSearchParams(window.location.search).get('account_id');
  if (fromQuery) {
    sessionStorage.setItem('nex_account_id', fromQuery);
    return fromQuery;
  }
  return sessionStorage.getItem('nex_account_id') || '';
}

function authHeaders() {
  const headers = { 'X-Account-Id': accountIdFromPath() };
  const raw = document.cookie
    .split('; ')
    .find((item) => item.startsWith('cw_d_session_info='));
  if (!raw) return headers;
  try {
    const data = JSON.parse(decodeURIComponent(raw.split('=').slice(1).join('=')));
    if (data['access-token']) {
      headers['access-token'] = data['access-token'];
      headers['token-type'] = data['token-type'] || 'Bearer';
      headers.client = data.client;
      headers.expiry = data.expiry;
      headers.uid = data.uid;
    }
  } catch {
    /* cookie malformado: a API ainda tenta o raw cookie */
  }
  return headers;
}

async function request(path, options = {}) {
  const headers = { ...authHeaders(), ...options.headers };
  if (!(options.body instanceof FormData)) {
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(`${API_ROOT}${path}`, {
    credentials: 'include',
    ...options,
    headers
  });
  if (response.status === 401) {
    const loginUrl = '/app/login';
    if (window.self !== window.top) window.parent.location.href = loginUrl;
    else window.location.href = loginUrl;
    throw new Error('Sessão expirada');
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (payload.reload) {
      throw Object.assign(new Error(payload.error || 'Recarregue a página'), { reload: true });
    }
    throw new Error(payload.error || 'Falha na API');
  }
  return payload;
}

export const api = {
  accountId: accountIdFromPath,
  session: () => request('/session'),
  users: () => request('/users'),
  list: (query) => request(`/chamados?${new URLSearchParams(query)}`),
  show: (number) => request(`/chamados/${encodeURIComponent(number)}`),
  byConversation: (id) => request(`/chamados/by-conversation/${id}`),
  create: (body) => request('/chamados', { method: 'POST', body: JSON.stringify(body) }),
  update: (number, body) =>
    request(`/chamados/${encodeURIComponent(number)}`, { method: 'PATCH', body: JSON.stringify(body) }),
  assume: (number) => request(`/chamados/${encodeURIComponent(number)}/assume`, { method: 'POST' }),
  leave: (number, reason) =>
    request(`/chamados/${encodeURIComponent(number)}/leave`, {
      method: 'POST',
      body: JSON.stringify({ reason })
    }),
  watch: (number) => request(`/chamados/${encodeURIComponent(number)}/watch`, { method: 'POST' }),
  unwatch: (number) => request(`/chamados/${encodeURIComponent(number)}/watch`, { method: 'DELETE' }),
  linkConversation: (number, conversationId) =>
    request(`/chamados/${encodeURIComponent(number)}/conversations`, {
      method: 'POST',
      body: JSON.stringify({ conversation_id: conversationId })
    }),
  unlinkConversation: (number, conversationId) =>
    request(`/chamados/${encodeURIComponent(number)}/conversations/${conversationId}`, { method: 'DELETE' }),
  linkContact: (number, contactId) =>
    request(`/chamados/${encodeURIComponent(number)}/contacts`, {
      method: 'POST',
      body: JSON.stringify({ contact_id: contactId })
    }),
  unlinkContact: (number, contactId) =>
    request(`/chamados/${encodeURIComponent(number)}/contacts/${contactId}`, { method: 'DELETE' }),
  attach: (number, file) => {
    const body = new FormData();
    body.append('file', file);
    return request(`/chamados/${encodeURIComponent(number)}/attachments`, { method: 'POST', body });
  },
  attachmentBlob: async (number, attachmentId) => {
    const accountId = accountIdFromPath();
    const query = accountId ? `?account_id=${encodeURIComponent(accountId)}` : '';
    const response = await fetch(
      `${API_ROOT}/chamados/${encodeURIComponent(number)}/attachments/${attachmentId}${query}`,
      { credentials: 'include', headers: authHeaders() }
    );
    if (response.status === 401) {
      const loginUrl = '/app/login';
      if (window.self !== window.top) window.parent.location.href = loginUrl;
      else window.location.href = loginUrl;
      throw new Error('Sessão expirada');
    }
    if (!response.ok) throw new Error('Não foi possível abrir o anexo');
    const blob = await response.blob();
    return { blob, type: blob.type || response.headers.get('content-type') || '' };
  },
  comments: (number) => request(`/chamados/${encodeURIComponent(number)}/comments`),
  addComment: (number, body, files = []) => {
    if (!files.length) {
      return request(`/chamados/${encodeURIComponent(number)}/comments`, {
        method: 'POST',
        body: JSON.stringify({ body })
      });
    }
    const payload = new FormData();
    payload.append('body', body || '');
    files.forEach((file) => payload.append('files[]', file));
    return request(`/chamados/${encodeURIComponent(number)}/comments`, { method: 'POST', body: payload });
  },
  attachmentUrl: (number, attachmentId) => {
    const accountId = accountIdFromPath();
    const query = accountId ? `?account_id=${encodeURIComponent(accountId)}` : '';
    return `${API_ROOT}/chamados/${encodeURIComponent(number)}/attachments/${attachmentId}${query}`;
  },
  destroy: (number) => request(`/chamados/${encodeURIComponent(number)}`, { method: 'DELETE' }),
  restore: (number) =>
    request(`/chamados/${encodeURIComponent(number)}/restore`, { method: 'POST' }),
  searchConversations: (q) => request(`/search/conversations?q=${encodeURIComponent(q)}`)
};
