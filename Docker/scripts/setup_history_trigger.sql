CREATE SCHEMA IF NOT EXISTS app_history;

CREATE TABLE IF NOT EXISTS app_history.message_history (
  id                SERIAL PRIMARY KEY,
  message_id        TEXT UNIQUE NOT NULL,
  key_id            TEXT,
  remote_jid        TEXT,
  from_me           BOOLEAN,
  instance_id       TEXT,
  content           JSONB,
  message_type      TEXT,
  message_timestamp BIGINT,
  deleted_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE app_history.message_history ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;

CREATE INDEX IF NOT EXISTS idx_message_history_key_id ON app_history.message_history(key_id);

CREATE OR REPLACE FUNCTION app_history.save_deleted_message()
RETURNS TRIGGER AS $$
DECLARE
  v_save_content JSONB;
  v_save_type    TEXT;
  v_key_id       TEXT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.message IS NOT NULL AND OLD.message::text != 'null')
       AND (NEW.message IS NULL OR NEW.message::text = 'null') THEN
      INSERT INTO app_history.message_history
        (message_id, key_id, remote_jid, from_me, instance_id, content, message_type, message_timestamp)
      VALUES (
        OLD.id,
        OLD.key->>'id',
        OLD.key->>'remoteJid',
        (OLD.key->>'fromMe')::boolean,
        OLD."instanceId",
        OLD.message,
        OLD."messageType",
        OLD."messageTimestamp"
      )
      ON CONFLICT (message_id) DO NOTHING;
    END IF;
    RETURN NEW;

  ELSIF TG_OP = 'INSERT' THEN
    IF (NEW.message IS NULL OR NEW.message::text = 'null') AND NEW.status = 'EDITED' THEN
      v_key_id := NEW.key->>'id';

      SELECT m.message, m."messageType"
      INTO v_save_content, v_save_type
      FROM "Message" m
      WHERE m.key->>'id' = v_key_id
        AND m."instanceId" = NEW."instanceId"
        AND m.message IS NOT NULL
        AND m.message::text != 'null'
        AND m.id != NEW.id
      ORDER BY m."messageTimestamp" DESC
      LIMIT 1;

      IF v_save_content IS NOT NULL THEN
        INSERT INTO app_history.message_history
          (message_id, key_id, remote_jid, from_me, instance_id, content, message_type, message_timestamp)
        VALUES (
          NEW.id,
          v_key_id,
          NEW.key->>'remoteJid',
          (NEW.key->>'fromMe')::boolean,
          NEW."instanceId",
          v_save_content,
          v_save_type,
          NEW."messageTimestamp"
        )
        ON CONFLICT (message_id) DO NOTHING;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS before_message_null ON "Message";
DROP TRIGGER IF EXISTS capture_deleted_message ON "Message";
DROP TRIGGER IF EXISTS capture_deleted_message_upd ON "Message";
DROP TRIGGER IF EXISTS capture_deleted_message_ins ON "Message";

CREATE TRIGGER capture_deleted_message_upd
  BEFORE UPDATE ON "Message"
  FOR EACH ROW EXECUTE FUNCTION app_history.save_deleted_message();

CREATE TRIGGER capture_deleted_message_ins
  AFTER INSERT ON "Message"
  FOR EACH ROW EXECUTE FUNCTION app_history.save_deleted_message();
