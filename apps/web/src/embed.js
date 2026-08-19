export function isEmbedded() {
  return window.self !== window.top;
}

export function openInChatwoot(url) {
  if (isEmbedded()) {
    window.parent.postMessage({ source: 'nex-chamados', action: 'open-conversation', url }, window.location.origin);
    return;
  }
  window.location.href = url;
}
