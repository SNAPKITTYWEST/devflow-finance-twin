-- ========================================================================
-- SOVEREIGN LEVIATHAN NODE LICENSE
-- License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
-- Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- ========================================================================
--
-- This file is a covered work under the GNU Affero General Public License,
-- version 3, together with the Sovereign Leviathan additional terms.
--
-- Hark, though this node be but a spark,
-- Its covenant endureth through the dark.
--
-- Ignorantia juris non excusat.
-- ========================================================================

-- ORCTASK: task queue table
CREATE TABLE ORC_SCHEMA.ORCTASK (
  TASKID         DECIMAL(15,0) NOT NULL PRIMARY KEY,
  CREATED_TS     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  SOURCE         VARCHAR(32),
  CHANNEL        VARCHAR(32),
  BACKEND        VARCHAR(16),
  PAYLOAD        CLOB(32K),
  PAYLOAD_LEN    INTEGER,
  STATUS         VARCHAR(8) DEFAULT 'NEW',
  RETRY_COUNT    INTEGER DEFAULT 0,
  NEXT_ATTEMPT_TS TIMESTAMP,
  LAST_ERROR     VARCHAR(256),
  LAST_UPD_TS    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ORCTASK_STATUS_IDX ON ORC_SCHEMA.ORCTASK (STATUS, NEXT_ATTEMPT_TS);

-- ORCLOG: operational log
CREATE TABLE ORC_SCHEMA.ORCLOG (
  LOG_TS    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  LEVEL     VARCHAR(6),
  MESSAGE   VARCHAR(1024),
  SOURCE    VARCHAR(64)
);

CREATE INDEX ORCLOG_TS_IDX ON ORC_SCHEMA.ORCLOG (LOG_TS);

-- ORCAUD: audit trail
CREATE TABLE ORC_SCHEMA.ORCAUD (
  TASKID     DECIMAL(15,0) NOT NULL,
  AUDIT_SEQ  INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
  EVENT_CODE VARCHAR(16),
  EVENT_TS   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  DETAIL     CLOB(8K),
  USER_ID    VARCHAR(32),
  PRIMARY KEY (TASKID, AUDIT_SEQ)
);

CREATE INDEX ORCAUD_TASKIDX ON ORC_SCHEMA.ORCAUD (TASKID);
