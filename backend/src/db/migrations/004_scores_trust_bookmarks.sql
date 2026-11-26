-- Thought scores, human checks for suspicious activity, and bookmarks.

-- How much a post looks thought through by a person, 0 to 100. Internal only:
-- it orders the 추천 feed and is never shown to the writer.
ALTER TABLE posts ADD COLUMN process_score smallint;  -- from the typing record
ALTER TABLE posts ADD COLUMN content_score smallint;  -- from the text itself
ALTER TABLE posts ADD COLUMN thought_score smallint;  -- the two combined

-- When the person last passed a typing check after activity looked automated.
ALTER TABLE users ADD COLUMN human_checked_at timestamptz;

-- One row per 공감, follow, report, block, post or failed check, for the
-- activity risk score. Rows older than a day are pruned.
CREATE TABLE action_log (
  user_id uuid NOT NULL,
  kind    text NOT NULL,
  at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX action_log_user_idx ON action_log (user_id, at DESC);

-- Posts a reader saved to read again. Only they see it.
CREATE TABLE bookmarks (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id    uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX bookmarks_user_idx ON bookmarks (user_id, created_at DESC);

-- People search by handle or name.
CREATE INDEX users_handle_lower_idx ON users (lower(handle) text_pattern_ops);
