-- create table of areas
-- CREATE TABLE mpa_area AS
-- SELECT
--   mpa_id AS id,
--   round((st_area (geom::geography) / 1000000)::numeric, 2) AS area_km2,
--   round((st_area (st_envelope (geom)::geography) / 1000000)::numeric, 2) AS bbox_area_km2,
--   st_numgeometries (geom) AS numgeom
-- FROM
--   mpa_mpa
-- WHERE
--   geom IS NOT NULL;
-- dedup - need better logic here
-- create table of ids to be dropped since they are not MPAs
-- TODO: verify that those rejected as MPA should not be visible in maps

CREATE TABLE mpa_drop AS
SELECT
  mpa_id id
FROM
  mpa_mpa
WHERE (geom IS NULL
  AND point_geom IS NULL)
  OR verification_state = 'Rejected as MPA';

-- to select nondups - needs work
-- SELECT DISTINCT ON (geom)
--   mpa_id id,
--   wdpa_id,
--   name,
--   country,
--   designation,
--   designation_eng,
--   is_mpa,
--   geom
-- FROM
--   mpa_mpa
-- WHERE
--   NOT is_point
--   AND geom IS NOT NULL;
--
-- TODO: deal with dups
-- create table of split geometries and areas

DROP TABLE mpa_poly CASCADE;

-- about 2 minutes to create
CREATE TABLE mpa_poly AS (
  WITH tmp AS (
  SELECT
    mpa_id id,
    (st_dump (geom)).geom::geometry AS geom
  FROM
    mpa_mpa
  WHERE
    NOT (geom IS NULL AND point_geom IS NULL) AND verification_state != 'Rejected as MPA'
)
  SELECT
    id, st_makevalid (geom) geom, round((st_area (geom::geography) / 1000000)::numeric, 2
) AS area_km2, round((st_area (st_envelope (geom)::geography) / 1000000)::numeric, 2
) AS bbox_area_km2
  FROM
    tmp
);

CREATE INDEX mpa_poly_geom_idx ON mpa_poly USING GIST (geom);

CREATE INDEX mpa_poly_id_idx ON mpa_poly (id);

CREATE TABLE mpa_core_atts AS
SELECT
  mpa_id id,
  name,
  country,
  designation,
  designation_eng
FROM
  mpa_mpa
WHERE (geom IS NULL
  AND point_geom IS NULL)
  OR verification_state = 'Rejected as MPA';

CREATE INDEX mpa_core_atts_id_idx ON mpa_core_atts (id);

-- try to regenerate stats used by query planner; they seem slow
VACUUM ANALYZE mpa_poly,
mpa_core_atts;

-- create simplified versions of large polygons
-- arbitrary threshold of 200 km2 and simplifying by 100m; yields about 800 polys
-- can probably simplify up to 1000m with little noticeable impact at global scale down to z4?  z6?  However, too big a simplification level drops polys.
-- can't see much of 100-200 km2 areas at Z4 or below

CREATE VIEW v_mpa_large_poly AS
SELECT
  st_transform (st_simplify (st_transform (geom,
        _ST_BestSRID (geom)),
      100),
    4326) AS geom,
  mpa_core_atts.*
FROM
  mpa_poly
  INNER JOIN mpa_core_atts ON (mpa_poly.id = mpa_core_atts.id)
WHERE
  area_km2 >= 200
ORDER BY
  id;

-- TO ANALYZE difference IN areas AND number OF points per poly FOR large areas:
WITH tmp AS (
  SELECT
    st_transform (st_simplify (st_transform (geom,
          _ST_BestSRID (geom)),
        10000),
      4326) AS geom_simp10000,
    st_transform (st_simplify (st_transform (geom, _ST_BestSRID (geom)), 1000), 4326) AS geom_simp1000,
    st_transform (st_simplify (st_transform (geom, _ST_BestSRID (geom)), 100), 4326) AS geom_simp100,
    geom,
    mpa_core_atts.*
  FROM
    mpa_poly
    INNER JOIN mpa_core_atts ON (mpa_poly.id = mpa_core_atts.id)
  WHERE
    area_km2 >= 100
  ORDER BY
    id
)
SELECT
  -- tmp.*,
  round((st_area (tmp.geom::geography) / 1000000)::numeric, 2) AS area_orig,
  round((st_area (tmp.geom_simp100::geography) / 1000000)::numeric, 2) AS area_simp100,
  round((st_area (tmp.geom_simp1000::geography) / 1000000)::numeric, 2) AS area_simp1000,
  round((st_area (tmp.geom_simp10000::geography) / 1000000)::numeric, 2) AS area_simp10000,
  st_npoints (geom),
  st_npoints (geom_simp100),
  st_npoints (geom_simp1000),
  st_npoints (geom_simp10000)
FROM
  tmp
LIMIT 100;

-- Create a view of mpas with core attributes for export to mbtiles, simplified to 1m
CREATE VIEW v_mpa_poly_simp AS
WITH tmp AS (
  SELECT
    st_transform (st_simplify (st_transform (geom,
          _ST_BestSRID (geom)),
        1),
      4326) geom,
    mpa_core_atts.*
  FROM
    mpa_poly
    INNER JOIN mpa_core_atts ON (mpa_poly.id = mpa_core_atts.id))
SELECT
  *
FROM
  tmp
WHERE
  geom IS NOT NULL;

-- Split countries from EEZ dataset (very big & slow dataset)
DROP TABLE eez_poly CASCADE;

CREATE TABLE eez_poly AS (
  WITH tmp AS (
  SELECT
    country,
    (st_dump (geom)).geom::geometry AS geom
  FROM
    spatialdata_eez
  WHERE
    geom IS NOT NULL
)
  SELECT
    country, st_makevalid (geom) geom, round((st_area (geom::geography) / 1000000)::numeric, 2
) AS area_km2, round((st_area (st_envelope (geom)::geography) / 1000000)::numeric, 2
) AS bbox_area_km2
  FROM
    tmp
);

CREATE INDEX eez_poly_geom_idx ON eez_poly USING GIST (geom);

CREATE INDEX eez_poly_country_idx ON eez_poly (country);

-- subdivide tables for faster joins
-- 800s

CREATE TABLE eez_poly_subdivided AS
SELECT
  country,
  st_subdivide (geom) AS geom
FROM
  eez_poly
ORDER BY
  country;

CREATE INDEX eez_poly_subdivided_geom_idx ON eez_poly_subdivided USING GIST (geom);

CREATE TABLE mpa_poly_subdivided AS
SELECT
  id,
  st_subdivide (geom) AS geom,
  area_km2,
  bbox_area_km2
FROM
  mpa_poly
ORDER BY
  id;

CREATE INDEX mpa_poly_subdivided_geom_idx ON mpa_poly_subdivided USING GIST (geom);

CREATE TABLE mpa_eez_poly_sjoin AS
SELECT
  id,
  country,
  mpa_poly_subdivided.area_km2 mpa_area_km2,
  round((st_area (st_intersection (mpa_poly_subdivided.geom, eez_poly_subdivided.geom)::geography) / 1000000)::numeric, 3) AS overlap_km2
FROM
  mpa_poly_subdivided,
  eez_poly_subdivided
WHERE
  st_intersects (mpa_poly_subdivided.geom, eez_poly_subdivided.geom);

