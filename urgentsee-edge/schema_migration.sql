-- Add app installation tracking columns to trust_circles
ALTER TABLE trust_circles ADD COLUMN has_app_installed INTEGER DEFAULT 1;
ALTER TABLE trust_circles ADD COLUMN last_seen_at TIMESTAMP;

-- Add index for last_seen_at queries
CREATE INDEX IF NOT EXISTS idx_trust_circles_last_seen ON trust_circles(last_seen_at);
