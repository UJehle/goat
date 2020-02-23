DROP FUNCTION IF EXISTS trim_loose_ends;
CREATE OR REPLACE FUNCTION public.trim_loose_ends(geom geometry)
 RETURNS trimmed_geom geometry 
 LANGUAGE plpgsql
AS $function$



BEGIN 
	SELECT COUNT (t.id) AS id_end from footpaths_union_temp t
	WHILE id < id_end LOOP 
		SELECT n.id, st_union(n.geom) AS geom_union FROM footpaths_union_temp n WHERE id <> n.id;
		RETURN NEXT st_intersects(geom_union,t.geom);
	END LOOP; 
	
END;



	-- i IN 
	--	SELECT 	t.id AS id, 
	--			t.geom AS geom 
	--	FROM footpaths_union_temp t
	--LOOP
	--		SELECT n.id, st_union(n.geom) AS geom_union FROM footpaths_union_temp n WHERE i.id <> n.id
	--END LOOP;
	




--SELECT st_union(t.geom) as geom_union 
	--FROM footpaths_union_temp t, footpaths_union_temp n
	--WHERE st_intersects(t.geom,n.geom) 
	--AND t.id <> n.id


--SELECT ST_Split(circle, line)
--FROM (SELECT
    --ST_MakeLine(ST_MakePoint(10, 10),ST_MakePoint(190, 190)) As line,
    --ST_Buffer(ST_GeomFromText('POINT(100 90)'), 50) As circle) As foo;