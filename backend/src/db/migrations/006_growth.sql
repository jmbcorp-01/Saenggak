-- Growth without ad spend: sharing consent, invite links and where people came
-- from, the promotion queue the promo agent fills, and the daily question.

-- Whether the writer lets Saenggak's own accounts and public pages show their
-- posts. Off until they turn it on. With share_anonymous the name is left out.
ALTER TABLE users ADD COLUMN share_ok boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN share_anonymous boolean NOT NULL DEFAULT false;
-- The person's own invite code, made the first time they ask for their link.
ALTER TABLE users ADD COLUMN invite_code text UNIQUE;
-- One post kept out of sharing while the rest are allowed.
ALTER TABLE posts ADD COLUMN share_excluded boolean NOT NULL DEFAULT false;

-- Link codes that are not a person's invite: one per promo post, and any an
-- admin makes for a community post or event.
CREATE TABLE link_codes (
  code       text PRIMARY KEY,
  channel    text NOT NULL,             -- 'instagram' | 'threads' | 'community' | 'web' | ...
  label      text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- The start button on public post pages.
INSERT INTO link_codes (code, channel, label) VALUES ('web-post', 'web', 'public post pages');

-- A visit to /i/{code}. Only the code and the kind of device: no address.
CREATE TABLE link_clicks (
  id       bigserial PRIMARY KEY,
  code     text NOT NULL,
  platform text NOT NULL,                -- 'ios' | 'android' | 'web'
  at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX link_clicks_code_idx ON link_clicks (code, at DESC);

-- Where a person came from, recorded once, in the first day after sign-up.
CREATE TABLE signup_sources (
  user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  code        text NOT NULL,
  channel     text NOT NULL,             -- 'invite' for a person's code, else the link code's channel
  referrer_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX signup_sources_code_idx ON signup_sources (code);

-- Posts the promo agent picked for Saenggak's own accounts. post_id has no
-- foreign key: when a post or account goes, the agent marks its item
-- withdrawn (or, once posted, for takedown) instead of losing track of it.
CREATE TABLE promo_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id       uuid NOT NULL,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'skipped', 'posted', 'failed', 'withdrawn', 'takedown')),
  caption       text NOT NULL DEFAULT '',
  score         integer NOT NULL DEFAULT 0,
  link_code     text NOT NULL,
  card_key      text,                    -- the card image in the photos bucket, once an admin approved it
  scheduled_for timestamptz,
  posted        jsonb NOT NULL DEFAULT '{}',   -- channel -> id of the post there
  error         text,
  decided_by    uuid,
  decided_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX promo_items_post_idx ON promo_items (post_id);
CREATE INDEX promo_items_status_idx ON promo_items (status, created_at DESC);

-- A question shown above the editor on its day, drafted weekly by the agent
-- and shown only once an admin approved it.
CREATE TABLE daily_questions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day        date NOT NULL UNIQUE,
  text_ko    text NOT NULL,
  text_en    text NOT NULL,
  status     text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- The dashboard counts by day.
CREATE INDEX IF NOT EXISTS users_created_idx ON users (created_at);
CREATE INDEX IF NOT EXISTS empathies_user_created_idx ON empathies (user_id, created_at);
