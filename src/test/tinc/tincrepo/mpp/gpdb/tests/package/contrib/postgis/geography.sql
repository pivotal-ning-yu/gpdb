-- start_ignore
-- ST_Area
-- ST_AsBinary
-- ST_AsEWKT
-- ST_AsGML
-- ST_AsGeoJSON
-- ST_AsKML
-- ST_AsSVG
-- ST_AsText
-- ST_Azimuth
-- ST_Buffer
-- ST_CoveredBy
-- ST_Covers
-- ST_DWithin
-- ST_Distance
-- ST_GeogFromText
-- ST_GeogFromWKB
-- ST_GeographyFromText
-- =
-- ST_Intersection
-- ST_Intersects
-- ST_Length
-- ST_Perimeter
-- ST_Project
-- ST_Summary
-- &&


DROP TABLE IF EXISTS geography_test;
-- end_ignore
CREATE TABLE geography_test (id INT4, name text, geog GEOGRAPHY);

INSERT INTO geography_test(id, name, geog) VALUES (1, 'A1', 'POINT(10 10)');
INSERT INTO geography_test(id, name, geog) VALUES (11, 'A2', 'POINT(10 30)');
INSERT INTO geography_test(id, name, geog) VALUES (2, 'B', 'POLYGON((1 1, 2 2, 2 4, 4 2, 1 1))');
INSERT INTO geography_test(id, name, geog) VALUES (3, 'C', 'MULTIPOLYGON(((0 0,4 0,4 4,0 4,0 0),(1 1,2 1,2 2,1 2,1 1)), ((-1 -1,-1 -2,-2 -2,-2 -1,-1 -1)))');
INSERT INTO geography_test(id, name, geog) VALUES (4, 'D', 'MULTILINESTRING((0 0,1 1,1 2),(2 3,3 2,5 4))');
INSERT INTO geography_test(id, name, geog) VALUES (5, 'A1', 'LINESTRINg(1 1, 2 2, 2 3, 3 3)');

SELECT GeometryType(geog) FROM geography_test ORDER BY id;

SELECT id, name, ST_AsGML(geog) FROM geography_test;
SELECT id, name, ST_AsText(geog), ST_AsBinary(geog), ST_AsEWKT(geog), ST_AsGeoJSON(geog), ST_AsKML(geog), ST_AsSVG(geog)  FROM geography_test ORDER BY id;

SELECT ST_Azimuth(ST_GeogFromText('POINT(10 10)'), ST_GeogFromText('POINT(10 30)')) FROM geography_test ORDER BY id;
SELECT ST_Azimuth(ST_GeogFromText('POINT(10 10)'), ST_GeogFromText('POINT(30 10)')) FROM geography_test ORDER BY id;

SELECT ST_AsText(ST_SnapToGrid(ST_Buffer(ST_GeogFromText(ST_AsText(geog)), 1)::geometry, 0.00001)) FROM geography_test ORDER BY id;

SELECT ST_CoveredBy(geog, ST_GeogFromText('POLYGON((1 1, 5 1, 10 2, 2 5, 1 1))')) FROM geography_test WHERE GeometryType(geog) = 'POINT' ORDER BY id;

SELECT ST_Covers(ST_GeogFromText('POLYGON((1 1, 5 1, 10 2, 2 5, 1 1))'), geog) FROM geography_test WHERE GeometryType(geog) = 'POINT' ORDER BY id;

SELECT ST_DWithin(geog, geog, 1) FROM geography_test ORDER BY id;

SELECT a.id, a.name, b.name FROM geography_test a LEFT JOIN geography_test b ON ST_DWithin(a.geog, b.geog, 100000);

SELECT ST_Distance(geog, ST_GeomFromText('POINT(10 10)', 4326)), ST_Distance(geog, ST_GeomFromText('POINT(0 0)', 4326)) FROM geography_test ORDER BY id;

SELECT ST_GeogFromText(ST_AsText(geog)), ST_GeogFromWKB(ST_AsBinary(geog)), ST_GeographyFromText(ST_AsText(geog)) FROM geography_test ORDER BY id;

SELECT ST_AsText(ST_Intersection(geog, ST_GeogFromText('POLYGON((1 1, 5 1, 10 2, 2 5, 1 1))'))) FROM geography_test ORDER BY id;

SELECT ST_Intersects(geog, ST_GeogFromText('POLYGON((1 1, 5 1, 10 2, 2 5, 1 1))')) FROM geography_test ORDER BY id;

--SELECT ST_Length(ST_GeogFromText('LINESTRING(1 1, 5 1, 10 2, 2 5)')) ORDER BY id;
SELECT id, name, ST_Length(geog) FROM geography_test ORDER BY id;

SELECT ST_AsText(geog), ST_Perimeter(geog::geometry) FROM geography_test ORDER BY id;

SELECT ST_AsText(geog), ST_Summary(geog) FROM geography_test ORDER BY id;

SELECT ST_AsText(geog), geog && ST_GeogFromText('LINESTRING(1 1, 5 1, 10 2, 2 5)') FROM geography_test ORDER BY id;

DROP TABLE geography_test;


-- Test the operator && with restrict (geography_gist_selectivity) and join (geography_gist_join_selectivity) functions
DROP TABLE IF EXISTS airports;
CREATE TABLE airports(code VARCHAR(3),geog GEOGRAPHY);
INSERT INTO airports VALUES ('LAX', 'POINT(-118.4079 33.9434)');
INSERT INTO airports VALUES ('CDG', 'POINT(2.5559 49.0083)');
INSERT INTO airports VALUES ('KEF', 'POINT(-22.6056 63.9850)');

-- Update pg_statistic manually because calling `analyze airports(geog)` does not call geography_analyze as expected
SET allow_system_table_mods='DML';
UPDATE pg_statistic SET stanumbers1='{3,0,0,0,0,-0.399923,-0.733488,0.556672,0,0.660547,0.0330462,0.900381,0,3,3,3,3,0,3}' WHERE starelid ='airports'::regclass AND staattnum=2;
UPDATE pg_statistic SET stakind1=101 WHERE starelid ='airports'::regclass AND staattnum=2;
-- Test restrict (geography_gist_selectivity) function
SELECT * FROM airports WHERE geog && '0101000020E61000006DC5FEB27B720440454772F90F814840'::geography;
-- Test join (geography_gist_join_selectivity) function
SELECT * FROM airports a1  JOIN airports a2  ON a1.geog && a2.geog;
DROP TABLE airports;
RESET allow_system_table_mods;
