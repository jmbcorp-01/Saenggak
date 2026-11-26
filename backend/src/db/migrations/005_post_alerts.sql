-- Alerts for new posts from a person one follows. Off unless the follower
-- turns on the bell on that person's profile; only posts written after that
-- moment are announced.
ALTER TABLE follows ADD COLUMN alerts_since timestamptz;
CREATE INDEX follows_alerts_idx ON follows (follower_id) WHERE alerts_since IS NOT NULL;
CREATE INDEX IF NOT EXISTS posts_author_created_idx ON posts (author_id, created_at DESC);
