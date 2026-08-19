export const STATUS_LABELS = {
  pendente: 'Pendente',
  em_atendimento: 'Em atendimento',
  resolvido: 'Resolvido',
  cancelado: 'Cancelado'
};

export function statusLabel(status) {
  return STATUS_LABELS[status] || status;
}
