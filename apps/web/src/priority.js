export const PRIORITY_LABELS = {
  baixa: 'Baixa',
  media: 'Média',
  alta: 'Alta'
};

export function priorityLabel(priority) {
  if (!priority) return '—';
  return PRIORITY_LABELS[priority] || priority;
}
