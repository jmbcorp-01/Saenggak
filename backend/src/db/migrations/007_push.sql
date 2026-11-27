-- Push alerts outside the app: each device's token, which kinds the person
-- wants, and how far the sender has looked for new events for them.

CREATE TABLE push_tokens (
  token      text PRIMARY KEY,                -- the Firebase Cloud Messaging registration token
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform   text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  created_at timestamptz NOT NULL DEFAULT now(),
  seen_at    timestamptz NOT NULL DEFAULT now()  -- last time the app registered it
);
CREATE INDEX push_tokens_user_idx ON push_tokens (user_id);

-- Each kind is on until the person turns it off in settings.
ALTER TABLE users ADD COLUMN push_empathy boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN push_follow boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN push_posts boolean NOT NULL DEFAULT true;
-- Events after this moment have not been pushed yet.
ALTER TABLE users ADD COLUMN push_checked_at timestamptz NOT NULL DEFAULT now();
