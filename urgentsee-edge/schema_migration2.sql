-- Add until_received and retry tracking to rush_alerts
ALTER TABLE rush_alerts ADD COLUMN until_received INTEGER DEFAULT 0;
ALTER TABLE rush_alerts ADD COLUMN retry_count INTEGER DEFAULT 0;
ALTER TABLE rush_alerts ADD COLUMN max_retries INTEGER DEFAULT 0;
