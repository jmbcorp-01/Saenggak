-- Admin tools: suspensions, review of held posts, and a log of every admin action.

ALTER TABLE users ADD COLUMN suspended_at timestamptz;
ALTER TABLE users ADD COLUMN suspended_reason text;

-- A blocked post an admin has looked at. Approved posts become published.
ALTER TABLE posts ADD COLUMN reviewed_at timestamptz;
ALTER TABLE posts ADD COLUMN reviewed_by uuid;
-- Set when an admin took a published post down.
ALTER TABLE posts ADD COLUMN removed_by uuid;

CREATE INDEX posts_review_idx ON posts (created_at DESC) WHERE status = 'blocked' AND reviewed_at IS NULL;

CREATE TABLE admin_actions (
  id        bigserial PRIMARY KEY,
  admin_id  uuid NOT NULL,
  action    text NOT NULL,    -- 'publish' | 'keep_blocked' | 'remove_post' | 'suspend' | 'unsuspend' | 'remove_photo'
  target_id uuid NOT NULL,    -- the post or user acted on
  note      text NOT NULL DEFAULT '',
  at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_actions_target_idx ON admin_actions (target_id, at DESC);
