-- Saenggak database schema (Aurora PostgreSQL with pgvector).
-- Apply once per environment; later changes go in numbered migrations.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE users (
  id              uuid PRIMARY KEY,                -- Cognito "sub"
  handle          text UNIQUE NOT NULL,
  display_name    text NOT NULL,
  bio             text NOT NULL DEFAULT '',
  photo_key       text,                            -- S3 key of the one allowed image
  locale          text NOT NULL DEFAULT 'ko',      -- 'ko' | 'en'
  time_zone       text NOT NULL DEFAULT 'Asia/Seoul',
  follow_unlocked boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE posts (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id      uuid NOT NULL REFERENCES users(id),
  body           text NOT NULL,
  lang           text NOT NULL,                    -- detected language of body
  typing_ms      integer NOT NULL,                 -- recomputed on the server
  local_date     date NOT NULL,                    -- writer's calendar day, for writing days
  status         text NOT NULL DEFAULT 'published' -- 'published' | 'blocked' | 'deleted'
                 CHECK (status IN ('published', 'blocked', 'deleted')),
  blocked_reason text,
  embedding      vector(1024),
  created_at     timestamptz NOT NULL DEFAULT now(),
  edited_at      timestamptz
);
CREATE INDEX posts_feed_idx ON posts (created_at DESC) WHERE status = 'published';
CREATE INDEX posts_author_idx ON posts (author_id, created_at DESC);
CREATE INDEX posts_embedding_idx ON posts USING hnsw (embedding vector_cosine_ops)
  WHERE status = 'published';

-- Raw typing sessions, kept for re-checking and abuse review.
CREATE TABLE typing_sessions (
  post_id     uuid PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
  session     jsonb NOT NULL,
  issues      text[] NOT NULL DEFAULT '{}'
);

CREATE TABLE empathies (
  post_id    uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE follows (
  follower_id uuid NOT NULL REFERENCES users(id),
  followee_id uuid NOT NULL REFERENCES users(id),
  hidden      boolean NOT NULL DEFAULT false,   -- hidden while follow permission is lost
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

-- First use of each normalized phrase ("처음 쓴 표현").
CREATE TABLE phrase_firsts (
  phrase_key text PRIMARY KEY,
  post_id    uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id  uuid NOT NULL REFERENCES users(id),
  shown_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Each time a writer lost follow permission (3 blocked posts in 30 days).
CREATE TABLE follow_losses (
  author_id uuid NOT NULL REFERENCES users(id),
  lost_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX follow_losses_author_idx ON follow_losses (author_id, lost_at DESC);

CREATE TABLE translations (
  post_id     uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  target_lang text NOT NULL,
  body        text NOT NULL,
  PRIMARY KEY (post_id, target_lang)
);

-- Days with at least one published post. Ten unlock following.
CREATE VIEW writing_days AS
  SELECT author_id, count(DISTINCT local_date) AS days
  FROM posts WHERE status = 'published'
  GROUP BY author_id;
