-- Reports, blocks and the notifications list.

-- A reader's report of a post (post_id set) or of a person (post_id null).
CREATE TABLE reports (
  id          bigserial PRIMARY KEY,
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- the person reported
  post_id     uuid REFERENCES posts(id) ON DELETE CASCADE,
  reason      text NOT NULL,                                         -- see REPORT_REASONS in the code
  note        text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid
);
-- One open report per reporter and post (or person), so repeated taps don't pile up.
CREATE UNIQUE INDEX reports_once_idx ON reports (reporter_id, user_id, coalesce(post_id, '00000000-0000-0000-0000-000000000000'))
  WHERE resolved_at IS NULL;
CREATE INDEX reports_open_idx ON reports (created_at DESC) WHERE resolved_at IS NULL;

-- Neither person sees the other's posts, and they cannot follow or 공감 each other.
CREATE TABLE blocks (
  blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX blocks_blocked_idx ON blocks (blocked_id);

-- Notifications are read from empathies and follows; this marks how far the person has read.
ALTER TABLE users ADD COLUMN notifications_seen_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX empathies_created_idx ON empathies (post_id, created_at DESC);
CREATE INDEX follows_followee_idx ON follows (followee_id, created_at DESC);
