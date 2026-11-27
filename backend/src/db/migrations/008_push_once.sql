-- Who has been alerted about what, so that undoing a 공감 or follow and
-- doing it again does not buzz the same person again. Kept for a day.

CREATE TABLE push_sent (
  user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- who got the alert
  kind     text NOT NULL CHECK (kind IN ('empathy', 'follow')),
  actor_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- The post for a 공감; the nil uuid for a follow.
  post_id  uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
  at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, kind, actor_id, post_id)
);
CREATE INDEX push_sent_at_idx ON push_sent (at);
