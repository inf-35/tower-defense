const SPREADSHEET_ID = "PUT_SPREADSHEET_ID_HERE";
const SHARED_SECRET = "PUT_SHARED_SECRET_HERE";

const RUN_SHEET = "run_summaries";
const SESSION_SHEET = "session_snapshots";
const TOWER_SHEET = "run_towers";
const RELIC_SHEET = "run_relics";
const RITE_SHEET = "run_rites";
const EVENT_ID_SHEET = "processed_event_ids";

const RUN_HEADERS = [
  "received_at_iso",
  "event_type",
  "game_name",
  "build_version",
  "session_id",
  "run_id",
  "difficulty",
  "environment",
  "result",
  "result_reason",
  "started_from_save",
  "run_duration_seconds",
  "session_duration_seconds",
  "session_runs_started",
  "session_runs_resumed",
  "session_runs_completed",
  "max_wave_reached",
  "final_wave_number",
  "placed_tower_counts_json",
  "collected_relic_counts_json",
  "collected_rite_counts_json",
  "raw_payload_json",
  "event_id",
];

const SESSION_HEADERS = [
  "received_at_iso",
  "event_type",
  "game_name",
  "build_version",
  "session_id",
  "snapshot_reason",
  "session_duration_seconds",
  "session_runs_started",
  "session_runs_resumed",
  "session_runs_completed",
  "active_run_id",
  "raw_payload_json",
  "event_id",
];

const COUNT_HEADERS = [
  "received_at_iso",
  "event_type",
  "game_name",
  "build_version",
  "session_id",
  "run_id",
  "difficulty",
  "environment",
  "result",
  "final_wave_number",
  "key",
  "count",
  "event_id",
];

const EVENT_ID_HEADERS = [
  "event_id",
  "received_at_iso",
  "event_type",
  "session_id",
];

function doGet(e) {
  try {
    const rawPayload = (e && e.parameter && e.parameter.payload) || "";
    if (rawPayload) {
      return _processEnvelope(JSON.parse(rawPayload));
    }
    return _json({ ok: true, endpoint: "alive" });
  } catch (error) {
    return _json({ ok: false, error: String(error) });
  }
}

function doPost(e) {
  try {
    const rawPayload =
      (e.parameter && e.parameter.payload) ||
      (e.postData && e.postData.contents) ||
      "{}";
    return _processEnvelope(JSON.parse(rawPayload));
  } catch (error) {
    return _json({ ok: false, error: String(error) });
  }
}

function _processEnvelope(envelope) {
  if (SHARED_SECRET && envelope.secret !== SHARED_SECRET) {
    return _json({ ok: false, error: "unauthorized" });
  }

  const eventId = _getEventId(envelope);
  const lock = eventId ? LockService.getScriptLock() : null;
  if (lock) {
    lock.waitLock(5000);
  }

  try {
    if (eventId && _hasProcessedEventId(eventId)) {
      return _json({ ok: true, duplicate: true });
    }

    if (envelope.event_type === "run_summary") {
      _appendRunRow(envelope);
    } else if (envelope.event_type === "session_snapshot" || envelope.event_type === "session_summary") {
      _appendSessionRow(envelope);
    }

    if (eventId) {
      _appendProcessedEventId(envelope);
    }
  } finally {
    if (lock) {
      lock.releaseLock();
    }
  }

  return _json({ ok: true });
}

function _appendRunRow(envelope) {
  const payload = envelope.payload || {};
  const receivedAt = new Date().toISOString();
  const sheet = _getSheet(RUN_SHEET, RUN_HEADERS);
  sheet.appendRow([
    receivedAt,
    envelope.event_type || "",
    envelope.game_name || "",
    envelope.build_version || "",
    envelope.session_id || "",
    payload.run_id || envelope.run_id || "",
    payload.difficulty || envelope.difficulty || "",
    payload.environment || envelope.environment || "",
    payload.result || envelope.result || "",
    payload.result_reason || "",
    Boolean(payload.started_from_save),
    Number(payload.run_duration_seconds || 0),
    Number(payload.session_duration_seconds || envelope.session_duration_seconds || 0),
    Number(payload.session_runs_started || 0),
    Number(payload.session_runs_resumed || 0),
    Number(payload.session_runs_completed || 0),
    Number(payload.max_wave_reached || envelope.max_wave_reached || 0),
    Number(payload.final_wave_number || 0),
    JSON.stringify(payload.placed_tower_counts || {}),
    JSON.stringify(payload.collected_relic_counts || {}),
    JSON.stringify(payload.collected_rite_counts || {}),
    JSON.stringify(payload),
    envelope.event_id || "",
  ]);

  _appendCountRows(TOWER_SHEET, receivedAt, envelope, payload, payload.placed_tower_counts || {});
  _appendCountRows(RELIC_SHEET, receivedAt, envelope, payload, payload.collected_relic_counts || {});
  _appendCountRows(RITE_SHEET, receivedAt, envelope, payload, payload.collected_rite_counts || {});
}

function _appendSessionRow(envelope) {
  const payload = envelope.payload || {};
  const sheet = _getSheet(SESSION_SHEET, SESSION_HEADERS);
  sheet.appendRow([
    new Date().toISOString(),
    envelope.event_type || "",
    envelope.game_name || "",
    envelope.build_version || "",
    envelope.session_id || "",
    payload.snapshot_reason || "",
    Number(payload.session_duration_seconds || envelope.session_duration_seconds || 0),
    Number(payload.session_runs_started || 0),
    Number(payload.session_runs_resumed || 0),
    Number(payload.session_runs_completed || 0),
    payload.active_run_id || "",
    JSON.stringify(payload),
    envelope.event_id || "",
  ]);
}

function _getSheet(name, headers) {
  const spreadsheet = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = spreadsheet.getSheetByName(name);
  if (!sheet) {
    sheet = spreadsheet.insertSheet(name);
  }
  _ensureHeaders(sheet, headers);
  return sheet;
}

function _ensureHeaders(sheet, headers) {
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(headers);
    return;
  }

  const lastColumn = sheet.getLastColumn();
  const currentHeaders = sheet.getRange(1, 1, 1, Math.max(lastColumn, 1)).getValues()[0];
  const existingHeaders = new Set(currentHeaders.filter((header) => header));
  const missingHeaders = headers.filter((header) => !existingHeaders.has(header));
  if (missingHeaders.length === 0) {
    return;
  }

  sheet.getRange(1, lastColumn + 1, 1, missingHeaders.length).setValues([missingHeaders]);
}

function _appendCountRows(sheetName, receivedAt, envelope, payload, counts) {
  const sheet = _getSheet(sheetName, COUNT_HEADERS);
  const entries = Object.entries(counts || {});
  if (entries.length === 0) {
    return;
  }

  const rows = entries.map(([key, count]) => [
    receivedAt,
    envelope.event_type || "",
    envelope.game_name || "",
    envelope.build_version || "",
    envelope.session_id || "",
    payload.run_id || envelope.run_id || "",
    payload.difficulty || envelope.difficulty || "",
    payload.environment || envelope.environment || "",
    payload.result || envelope.result || "",
    Number(payload.final_wave_number || 0),
    key,
    Number(count || 0),
    envelope.event_id || "",
  ]);

  sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, COUNT_HEADERS.length).setValues(rows);
}

function _getEventId(envelope) {
  return String((envelope && envelope.event_id) || "").trim();
}

function _hasProcessedEventId(eventId) {
  const sheet = _getSheet(EVENT_ID_SHEET, EVENT_ID_HEADERS);
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) {
    return false;
  }

  const values = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  return values.some((row) => String(row[0]) === eventId);
}

function _appendProcessedEventId(envelope) {
  const sheet = _getSheet(EVENT_ID_SHEET, EVENT_ID_HEADERS);
  sheet.appendRow([
    envelope.event_id || "",
    new Date().toISOString(),
    envelope.event_type || "",
    envelope.session_id || "",
  ]);
}

function _json(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
