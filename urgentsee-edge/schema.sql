CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    public_key TEXT NOT NULL,
    apns_token TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trust_circles (
    user_id TEXT NOT NULL,
    pal_id TEXT NOT NULL,
    status TEXT CHECK(status IN ('PENDING', 'ACTIVE', 'BLOCKED')) DEFAULT 'ACTIVE',
    has_app_installed INTEGER DEFAULT 1,
    last_seen_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, pal_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (pal_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rush_alerts (
    alert_id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    payload_ciphertext TEXT,
    raw_message_preview TEXT,
    is_critical INTEGER DEFAULT 1,
    ttl_minutes INTEGER DEFAULT 15,
    status TEXT CHECK(status IN ('PUSHED', 'MOUNTED', 'SEEN', 'EXPIRED')) DEFAULT 'PUSHED',
    expires_at TIMESTAMP NOT NULL,
    acknowledged_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sender_id) REFERENCES users(user_id),
    FOREIGN KEY (recipient_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS telemetry_events (
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

CREATE INDEX IF NOT EXISTS idx_rush_alerts_recipient ON rush_alerts(recipient_id, status);
CREATE INDEX IF NOT EXISTS idx_rush_alerts_expires ON rush_alerts(expires_at);
CREATE INDEX IF NOT EXISTS idx_trust_circles_pair ON trust_circles(user_id, pal_id, status);
CREATE INDEX IF NOT EXISTS idx_trust_circles_last_seen ON trust_circles(last_seen_at);
