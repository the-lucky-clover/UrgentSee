-- UrgentSee tables (prefixed to avoid collisions with other apps sharing the account's D1 databases)
CREATE TABLE IF NOT EXISTS us_users (
    user_id TEXT PRIMARY KEY,
    public_key TEXT NOT NULL,
    apns_token TEXT,
    display_name TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS us_trust_circles (
    user_id TEXT NOT NULL,
    pal_id TEXT NOT NULL,
    status TEXT CHECK(status IN ('PENDING', 'ACTIVE', 'BLOCKED')) DEFAULT 'ACTIVE',
    has_app_installed INTEGER DEFAULT 1,
    last_seen_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, pal_id)
);

CREATE TABLE IF NOT EXISTS us_rush_alerts (
    alert_id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    payload_ciphertext TEXT,
    raw_message_preview TEXT,
    is_critical INTEGER DEFAULT 1,
    ttl_minutes INTEGER DEFAULT 15,
    until_received INTEGER DEFAULT 0,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 0,
    status TEXT CHECK(status IN ('PUSHED', 'MOUNTED', 'SEEN', 'EXPIRED')) DEFAULT 'PUSHED',
    expires_at TIMESTAMP NOT NULL,
    acknowledged_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS us_telemetry_events (
    event_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    event_type TEXT CHECK(event_type IN (
      'dispatch_apns_success',
      'dispatch_apns_failed',
      'trust_circle_invite',
      'trust_circle_accept',
      'trust_circle_block',
      'trust_circle_remove',
      'reverse_ack_received',
      'rate_limit_override'
    )) NOT NULL,
    latency_ms INTEGER,
    delivery_status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_us_trust_circles_pair ON us_trust_circles(user_id, pal_id, status);
CREATE INDEX IF NOT EXISTS idx_us_trust_circles_last_seen ON us_trust_circles(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_us_rush_recipient ON us_rush_alerts(recipient_id, status);
CREATE INDEX IF NOT EXISTS idx_us_rush_expires ON us_rush_alerts(expires_at);
