const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
const CLOSED_STATUSES = new Set(['resolvido', 'cancelado']);

export function showsOpenAge(status) {
  return !CLOSED_STATUSES.has(status);
}

export function formatElapsed(elapsedMs) {
  const elapsed = Math.max(0, elapsedMs);
  if (elapsed < MINUTE_MS) return '< 1 min';

  if (elapsed < HOUR_MS) {
    return `${Math.floor(elapsed / MINUTE_MS)} min`;
  }

  const hours = Math.floor(elapsed / HOUR_MS);
  const minutes = Math.floor((elapsed % HOUR_MS) / MINUTE_MS);
  if (elapsed < DAY_MS) {
    return minutes ? `${hours}h ${minutes}min` : `${hours}h`;
  }

  const days = Math.floor(elapsed / DAY_MS);
  const remainHours = Math.floor((elapsed % DAY_MS) / HOUR_MS);
  return remainHours ? `${days}d ${remainHours}h` : `${days}d`;
}

export function formatOpenAge(createdAt, now = Date.now()) {
  const start = new Date(createdAt).getTime();
  if (!createdAt || Number.isNaN(start)) return '—';

  return formatElapsed(now - start);
}

export function formatOpenAgeSeconds(seconds) {
  if (seconds == null || Number.isNaN(Number(seconds))) return '—';

  return formatElapsed(Math.max(0, Number(seconds)) * 1000);
}

export function openAgeForItem(item, now = Date.now()) {
  if (showsOpenAge(item?.status)) {
    return formatOpenAge(item.opened_at || item.created_at, now);
  }

  return formatOpenAgeSeconds(item?.last_open_seconds);
}
