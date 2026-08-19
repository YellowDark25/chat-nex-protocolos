DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolos'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_chamados'
  ) THEN
    ALTER TABLE nex_protocolos RENAME TO nex_chamados;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_assignees'
  ) THEN
    ALTER TABLE nex_protocolo_assignees RENAME TO nex_chamado_assignees;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_watchers'
  ) THEN
    ALTER TABLE nex_protocolo_watchers RENAME TO nex_chamado_watchers;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_conversations'
  ) THEN
    ALTER TABLE nex_protocolo_conversations RENAME TO nex_chamado_conversations;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_contacts'
  ) THEN
    ALTER TABLE nex_protocolo_contacts RENAME TO nex_chamado_contacts;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_attachments'
  ) THEN
    ALTER TABLE nex_protocolo_attachments RENAME TO nex_chamado_attachments;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_events'
  ) THEN
    ALTER TABLE nex_protocolo_events RENAME TO nex_chamado_events;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_sequences'
  ) THEN
    ALTER TABLE nex_protocolo_sequences RENAME TO nex_chamado_sequences;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_protocolo_comments'
  ) THEN
    ALTER TABLE nex_protocolo_comments RENAME TO nex_chamado_comments;
  END IF;
END $$;

DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name LIKE 'nex_chamado_%'
      AND column_name = 'protocolo_id'
  LOOP
    EXECUTE format('ALTER TABLE %I RENAME COLUMN protocolo_id TO chamado_id', rec.table_name);
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_chamado_assignees'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nex_chamado_participantes'
  ) THEN
    ALTER TABLE nex_chamado_assignees RENAME TO nex_chamado_participantes;
  END IF;
END $$;

ALTER INDEX IF EXISTS nex_protocolos_account_status_idx RENAME TO nex_chamados_account_status_idx;
ALTER INDEX IF EXISTS nex_protocolo_conversations_conv_idx RENAME TO nex_chamado_conversations_conv_idx;
ALTER INDEX IF EXISTS nex_protocolo_events_proto_idx RENAME TO nex_chamado_events_chamado_idx;
ALTER INDEX IF EXISTS nex_protocolo_comments_proto_idx RENAME TO nex_chamado_comments_chamado_idx;

CREATE TABLE IF NOT EXISTS nex_chamados (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL,
  number VARCHAR(32) NOT NULL,
  subject VARCHAR(255),
  assunto TEXT,
  status VARCHAR(32) NOT NULL DEFAULT 'pendente',
  priority VARCHAR(16),
  due_on DATE,
  opened_by_user_id BIGINT NOT NULL,
  opened_from_conversation_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (account_id, number)
);

CREATE INDEX IF NOT EXISTS nex_chamados_account_status_idx
  ON nex_chamados (account_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS nex_chamado_participantes (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (chamado_id, user_id)
);

CREATE TABLE IF NOT EXISTS nex_chamado_watchers (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (chamado_id, user_id)
);

CREATE TABLE IF NOT EXISTS nex_chamado_conversations (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  conversation_id BIGINT NOT NULL,
  display_id INTEGER,
  is_origin BOOLEAN NOT NULL DEFAULT FALSE,
  removed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (chamado_id, conversation_id)
);

CREATE INDEX IF NOT EXISTS nex_chamado_conversations_conv_idx
  ON nex_chamado_conversations (conversation_id);

ALTER TABLE nex_chamado_conversations ADD COLUMN IF NOT EXISTS label VARCHAR(255);

CREATE TABLE IF NOT EXISTS nex_chamado_contacts (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  contact_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (chamado_id, contact_id)
);

CREATE TABLE IF NOT EXISTS nex_chamado_attachments (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  filename VARCHAR(255) NOT NULL,
  content_type VARCHAR(128),
  byte_size INTEGER NOT NULL DEFAULT 0,
  storage_key VARCHAR(512) NOT NULL,
  uploaded_by_user_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nex_chamado_events (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  event_type VARCHAR(64) NOT NULL,
  actor_user_id BIGINT,
  payload JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS nex_chamado_events_chamado_idx
  ON nex_chamado_events (chamado_id, created_at DESC);

CREATE TABLE IF NOT EXISTS nex_chamado_sequences (
  account_id BIGINT NOT NULL,
  year INTEGER NOT NULL,
  last_value INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, year)
);

ALTER TABLE nex_chamados ADD COLUMN IF NOT EXISTS assunto TEXT;

CREATE TABLE IF NOT EXISTS nex_chamado_comments (
  id BIGSERIAL PRIMARY KEY,
  chamado_id BIGINT NOT NULL REFERENCES nex_chamados(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS nex_chamado_comments_chamado_idx
  ON nex_chamado_comments (chamado_id, created_at ASC);

ALTER TABLE nex_chamado_attachments
  ADD COLUMN IF NOT EXISTS comment_id BIGINT REFERENCES nex_chamado_comments(id) ON DELETE CASCADE;

UPDATE nex_chamado_events
SET event_type = 'chamado_aberto'
WHERE event_type = 'protocolo_aberto';

ALTER TABLE nex_chamados ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ;
ALTER TABLE nex_chamados ADD COLUMN IF NOT EXISTS last_open_seconds INTEGER;

UPDATE nex_chamados AS chamado
SET opened_at = COALESCE(
  (
    SELECT reopen.created_at
    FROM nex_chamado_events AS reopen
    WHERE reopen.chamado_id = chamado.id
      AND reopen.event_type = 'status'
      AND reopen.payload->>'from' IN ('resolvido', 'cancelado')
      AND reopen.payload->>'to' IN ('pendente', 'em_atendimento')
    ORDER BY reopen.created_at DESC
    LIMIT 1
  ),
  chamado.created_at
)
WHERE chamado.opened_at IS NULL;

UPDATE nex_chamados AS chamado
SET last_open_seconds = (
  SELECT GREATEST(
    0,
    EXTRACT(EPOCH FROM (
      close_event.created_at - COALESCE(
        (
          SELECT reopen.created_at
          FROM nex_chamado_events AS reopen
          WHERE reopen.chamado_id = chamado.id
            AND reopen.event_type = 'status'
            AND reopen.payload->>'from' IN ('resolvido', 'cancelado')
            AND reopen.payload->>'to' IN ('pendente', 'em_atendimento')
            AND reopen.created_at < close_event.created_at
          ORDER BY reopen.created_at DESC
          LIMIT 1
        ),
        (
          SELECT aberto.created_at
          FROM nex_chamado_events AS aberto
          WHERE aberto.chamado_id = chamado.id
            AND aberto.event_type IN ('chamado_aberto', 'protocolo_aberto')
          ORDER BY aberto.created_at ASC
          LIMIT 1
        ),
        chamado.created_at
      )
    ))::INTEGER
  )
  FROM nex_chamado_events AS close_event
  WHERE close_event.chamado_id = chamado.id
    AND close_event.event_type = 'status'
    AND close_event.payload->>'to' IN ('resolvido', 'cancelado')
  ORDER BY close_event.created_at DESC
  LIMIT 1
)
WHERE chamado.status IN ('resolvido', 'cancelado')
  AND chamado.last_open_seconds IS NULL;

UPDATE nex_chamado_events AS event
SET payload = event.payload || jsonb_build_object(
  'open_seconds',
  GREATEST(
    0,
    EXTRACT(EPOCH FROM (
      event.created_at - COALESCE(
        (
          SELECT reopen.created_at
          FROM nex_chamado_events AS reopen
          WHERE reopen.chamado_id = event.chamado_id
            AND reopen.event_type = 'status'
            AND reopen.payload->>'from' IN ('resolvido', 'cancelado')
            AND reopen.payload->>'to' IN ('pendente', 'em_atendimento')
            AND reopen.created_at < event.created_at
          ORDER BY reopen.created_at DESC
          LIMIT 1
        ),
        (
          SELECT aberto.created_at
          FROM nex_chamado_events AS aberto
          WHERE aberto.chamado_id = event.chamado_id
            AND aberto.event_type IN ('chamado_aberto', 'protocolo_aberto')
          ORDER BY aberto.created_at ASC
          LIMIT 1
        ),
        (
          SELECT chamado.created_at
          FROM nex_chamados AS chamado
          WHERE chamado.id = event.chamado_id
        )
      )
    ))::INTEGER
  )
)
WHERE event.event_type = 'status'
  AND event.payload->>'from' IN ('pendente', 'em_atendimento')
  AND event.payload->>'to' IN ('resolvido', 'cancelado')
  AND event.payload->>'open_seconds' IS NULL;

ALTER TABLE nex_chamado_attachments ADD COLUMN IF NOT EXISTS transcript TEXT;

ALTER TABLE nex_chamados ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE nex_chamados ADD COLUMN IF NOT EXISTS deleted_by_user_id BIGINT;

CREATE INDEX IF NOT EXISTS nex_chamados_account_visible_idx
  ON nex_chamados (account_id, status, updated_at DESC)
  WHERE deleted_at IS NULL;
