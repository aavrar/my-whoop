-- One-time correction: the strap RTC was ~529 days behind, so all strap-recorded data landed in
-- Dec 2024 instead of late-May 2026. Shift strap-sourced timestamps forward by 529 days and drop
-- the stale strap-computed daily/sleep rows so the engine recomputes them at the correct dates.
-- Idempotent: only rows before 2026-01-01 are touched. CSV-imported baseline rows are left alone.
-- 529 days = 45,705,600 s.  2026-01-01 UTC = 1767225600.  2024 RTC floor = 1700000000.
BEGIN;
UPDATE hrSample       SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE rrInterval     SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE gravitySample  SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE spo2Sample     SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE skinTempSample SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE respSample     SET ts = ts + 45705600 WHERE ts < 1767225600;
UPDATE event          SET ts = ts + 45705600 WHERE ts > 1700000000 AND ts < 1767225600;
UPDATE battery        SET ts = ts + 45705600 WHERE ts > 1700000000 AND ts < 1767225600;
UPDATE sleepSession   SET startTs = startTs + 45705600, endTs = endTs + 45705600
                      WHERE stagesJSON IS NOT NULL AND startTs < 1767225600;
DELETE FROM dailyMetric WHERE disturbances IS NOT NULL;
DELETE FROM dailyMetric WHERE recovery IS NULL AND strain IS NULL AND totalSleepMin IS NULL;
COMMIT;
