import { formatOpenAgeSeconds } from './openAge.js';
import { statusLabel } from './status.js';

const EVENT_TITLES = {
  chamado_aberto: 'Chamado aberto',
  protocolo_aberto: 'Chamado aberto',
  assumiu: 'Atendimento assumido',
  largou: 'Participante abandonou o atendimento',
  observando: 'Passou a observar',
  parou_observar: 'Parou de observar',
  conversa_vinculada: 'Conversa vinculada',
  conversa_desvinculada: 'Conversa desvinculada',
  contato_vinculado: 'Contato vinculado',
  contato_desvinculado: 'Contato desvinculado',
  anexo: 'Arquivo anexado',
  status: 'Status alterado',
  apagou: 'Chamado movido para a lixeira',
  restaurou: 'Chamado restaurado'
};

function actorName(event, payload) {
  if (event?.actor?.name) return event.actor.name;
  const userId = payload.user_id || event?.actor_user_id;
  return userId ? `#${userId}` : '';
}

function eventTitle(type, event, payload) {
  const name = actorName(event, payload);
  if (type === 'observando') {
    return name ? `${name} passou a observar` : 'Alguém passou a observar';
  }
  if (type === 'parou_observar') {
    return name ? `${name} parou de observar` : 'Alguém parou de observar';
  }
  if (type === 'assumiu') {
    return name ? `${name} assumiu o atendimento` : EVENT_TITLES.assumiu;
  }
  if (type === 'largou') {
    return name ? `${name} abandonou o atendimento` : EVENT_TITLES.largou;
  }
  if (type === 'apagou') {
    return name ? `${name} moveu o chamado para a lixeira` : EVENT_TITLES.apagou;
  }
  if (type === 'restaurou') {
    return name ? `${name} restaurou o chamado` : EVENT_TITLES.restaurou;
  }
  return EVENT_TITLES[type] || type;
}

function eventPayload(event) {
  const payload = event?.payload;
  if (!payload) return {};
  if (typeof payload === 'string') {
    try {
      const parsed = JSON.parse(payload);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (error) {
      console.warn('Payload da timeline inválido', error);
      return {};
    }
  }
  return typeof payload === 'object' ? payload : {};
}

function conversationLabel(payload) {
  const displayId = payload.display_id || payload.conversation_id;
  return displayId ? `#${displayId}` : '';
}

function eventDetail(type, payload) {
  switch (type) {
    case 'chamado_aberto':
    case 'protocolo_aberto':
      return [conversationLabel(payload) && `A partir da conversa ${conversationLabel(payload)}`, payload.assunto]
        .filter(Boolean)
        .join(' · ');
    case 'conversa_vinculada':
    case 'conversa_desvinculada':
      return conversationLabel(payload);
    case 'contato_vinculado':
    case 'contato_desvinculado':
      return payload.contact_id ? `#${payload.contact_id}` : '';
    case 'anexo':
      return payload.filename || '';
    case 'status':
      return [
        `${statusLabel(payload.from)} → ${statusLabel(payload.to)}`,
        payload.open_seconds != null ? `Aberto por ${formatOpenAgeSeconds(payload.open_seconds)}` : null,
        payload.reason
      ]
        .filter(Boolean)
        .join(' · ');
    case 'largou':
      return payload.reason || '';
    default:
      return '';
  }
}

export function formatTimelineEvent(event) {
  const type = event?.type || '';
  const payload = eventPayload(event);
  return {
    title: eventTitle(type, event, payload),
    detail: eventDetail(type, payload),
    at: event?.created_at ? new Date(event.created_at).toLocaleString('pt-BR') : ''
  };
}
