-- start_ignore
----------------------------------------------------------------------------------
-- PURPOSE:
--     This is nearly identical to 
--         IndexedAOTablesBasicTests2/test04renameIndex.sql 
--     except that this uses gpfdist to load the table named "albums".
-- LAST MODIFIED:
--     2010-03-24 mgilkey
--         We removed the feature "unique indexes on AO tables" shortly before
--         the product release, so I had to modify several files in this test
--         to make unique indexes non-unique indexes, and remove primary keys
--         (which implicitly create a unique index).
----------------------------------------------------------------------------------
-- end_ignore

-- start_ignore
DROP TABLE IF EXISTS albums;
DROP EXTERNAL TABLE IF EXISTS externalRecords;
-- end_ignore

CREATE TABLE records (ID INTEGER, 
 title VARCHAR, 
 performer VARCHAR)
 WITH (APPENDONLY=True, ORIENTATION='column')
 DISTRIBUTED BY (id)
 ;

CREATE INDEX albumTitleIndex ON records USING BITMAP (title);

-- --- OLD
-- COPY records FROM '/tmp/albumData.txt' DELIMITER ',';
-- --- NEW
CREATE EXTERNAL TABLE externalRecords (LIKE records)
 LOCATION ('gpfdist://10.254.0.194/gpfdist2/data/albumData.txt')
 FORMAT 'CSV' (DELIMITER ',');
INSERT INTO records SELECT * FROM externalRecords;

SET enable_seqscan = False;

SELECT id, title, performer FROM records ORDER BY title;
SELECT id, performer, title FROM records ORDER BY performer;

-- Rename the table.
ALTER TABLE records RENAME TO albums;
-- Rename a column.  (In fact, we'll rename it twice.)
ALTER TABLE albums RENAME COLUMN performer TO "group";
ALTER TABLE albums RENAME COLUMN "group" TO band;


CREATE SCHEMA worstLaidSchemasOfMiceAndMen; 

ALTER TABLE albums SET SCHEMA worstLaidSchemasOfMiceAndMen;

-- Try to rename the index.  Presumably it should be part of the new schema.
ALTER INDEX worstLaidSchemasOfMiceAndMen.albumTitleIndex RENAME TO albumNameIndex;

ALTER INDEX worstLaidSchemasOfMiceAndMen.albumNameIndex SET (FILLFACTOR = 10);

-- This should fail because the table named "albums" is no longer in the 
-- current schema.
SELECT id, title, band FROM albums ORDER BY title, band;

-- These should succeed because we specified the schema.
SELECT id, title, band FROM worstLaidSchemasOfMiceAndMen.albums ORDER BY title;
SELECT id, band, title FROM worstLaidSchemasOfMiceAndMen.albums ORDER BY band;

-- start_ignore
DROP TABLE IF EXISTS worstLaidSchemasOfMiceAndMen.records;
DROP TABLE IF EXISTS worstLaidSchemasOfMiceAndMen.albums;
DROP SCHEMA IF EXISTS worstLaidSchemasOfMiceAndMen;
-- end_ignore


