-- overwrite intersection table
DROP TABLE IF EXISTS eez_mpas CASCADE;
CREATE TABLE eez_mpas AS 
SELECT m.mpa_id, e.fid, 
  CASE WHEN 
    ST_CoveredBy(m.geog, e.geom) 
  THEN 
    m.geog
  ELSE 
    ST_Multi(ST_Intersection(m.geog, e.geom)) 
  END AS geom 
FROM mpa_mpa AS m
  INNER JOIN eez AS e
  ON (
    ST_Intersects(m.geog, e.geom) AND 
    NOT ST_Touches(m.geog, e.geom) )
WHERE
  m.mpa_id = 68813321 AND 
  e.sov = 'ARG';

-- register geom
SELECT Populate_Geometry_Columns('eez_mpas'::regclass::oid);

-- calculate area
ALTER TABLE eez_mpas ADD COLUMN IF NOT EXISTS area_km2 double precision;
UPDATE eez_mpas SET area_km2=ROUND((ST_Area(geom::geography) / (1000*1000))::numeric,2);
