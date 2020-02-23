DROP FUNCTION IF EXISTS pois_multi_isochrones;
CREATE OR REPLACE FUNCTION public.pois_multi_isochrones(userid_input integer, d integer, h integer, m integer, minutes integer, speed_input numeric, 
	n integer, routing_profile_input text, alphashape_parameter_input NUMERIC, modus_input text,region_type text, region text[], amenities text[])
RETURNS SETOF type_pois_multi_isochrones
AS $function$ 
DECLARE 	
 	boundary_envelope numeric[];
 	i integer;
 	points_array numeric[][];
 	objectids_array integer [];
 	mask geometry;
 	buffer_mask geometry;
	buffer integer;
 	excluded_class_id integer[];
	categories_no_foot text[];
	wheelchair_condition text[];
	population_mask jsonb; 
	objectid_multi_isochrone integer;
	max_length_links numeric;
	calc_modus integer;
	BEGIN

	RAISE NOTICE 'd:%', d;
	RAISE NOTICE 'h:%', h;
	RAISE NOTICE 'm:%', m;

	/*Scenario building has to be implemented*/
    calc_modus = 1;
	buffer = (minutes::numeric/60::numeric)*speed_input*1000;
 
 	IF region_type = 'study_area' THEN
 		--Logic to intersect the amenities with a study area defined by name
		SELECT ST_Union(geom) AS geom, array_to_json(array_agg(jsonb_build_object(name,round(sum_pop,-1)))) 
		INTO mask, population_mask
		FROM study_area
		WHERE name IN (SELECT UNNEST(region));
		
		buffer_mask = ST_buffer(mask::geography,buffer)::geometry;
 	 
 	ELSE 
		boundary_envelope = region::numeric[];
		
		mask = ST_MakeEnvelope(boundary_envelope[1],boundary_envelope[2],boundary_envelope[3],boundary_envelope[4],4326);
	
		SELECT jsonb_build_object('bounding_box',round(sum(population)::integer,-1)) AS sum_pop
		INTO population_mask
		FROM population p 
		WHERE ST_Intersects(p.geom,mask);		
	
 		SELECT ST_Buffer(mask::geography,buffer)::geometry 
 		INTO buffer_mask;
	
 	END IF;

	-- Exclude POIs that are not accessible by wheelchair if routing_profile_input = wheelchair
	IF routing_profile_input = 'walking_wheelchair' THEN 
		wheelchair_condition = ARRAY['no','No'];
	ELSE 
		wheelchair_condition = NULL;
	END IF;

	RAISE NOTICE 'wheelchair_condition:%', wheelchair_condition;
	RAISE NOTICE 'buffer_mask:%', buffer_mask;

  	/*without or with opening hours*/
  	IF d = 9999 OR h = 9999 OR m = 9999 THEN 
		SELECT DISTINCT p_array
		INTO points_array
		FROM (
			SELECT array_agg(ARRAY[ST_X(p.geom)::numeric, ST_Y(p.geom)::numeric]) AS p_array
			FROM pois p
			WHERE p.amenity IN (SELECT UNNEST(amenities))
			AND (p.wheelchair NOT IN (SELECT UNNEST(wheelchair_condition)) OR p.wheelchair IS NULL)
			AND st_intersects(p.geom, buffer_mask)
			UNION ALL
			SELECT array_agg(ARRAY[ST_X(p.geom)::numeric, ST_Y(p.geom)::numeric]) AS p_array
			FROM public_transport_stops p
			WHERE p.public_transport_stop IN (SELECT UNNEST(amenities))
			AND (p.wheelchair NOT IN (SELECT UNNEST(wheelchair_condition)) OR p.wheelchair IS NULL)
			AND st_intersects(p.geom, buffer_mask)
		) x;
	ELSE 
		SELECT DISTINCT p_array
		INTO points_array
		FROM (
			SELECT array_agg(ARRAY[ST_X(p.geom)::numeric, ST_Y(p.geom)::numeric]) AS p_array
			FROM pois p
			WHERE p.amenity IN (SELECT UNNEST(amenities))
			AND (p.wheelchair NOT IN (SELECT UNNEST(wheelchair_condition)) OR p.wheelchair IS NULL)
			AND st_intersects(p.geom, buffer_mask)
			AND p.amenity IN (SELECT (UNNEST(select_from_variable_container('amenity_opening_hours'))))
			AND check_open(p.opening_hours,array[d,h,m]) = 'True'
		) x;
	END IF;

	RAISE NOTICE 'points_array:%', points_array;
 	---------------------------------------------------------------------------------
 	--------------------------get catchment of all starting points-------------------
 	---------------------------------------------------------------------------------
 
 
 		
	SELECT DISTINCT objectid 
	INTO objectid_multi_isochrone  
	FROM multi_isochrones(userid_input,minutes,n,routing_profile_input,speed_input,alphashape_parameter_input,calc_modus,1,points_array);
		
	IF region_type = 'study_area' THEN
	 	WITH expand_population AS 
		(
			SELECT m.gid,jsonb_array_elements(population_mask) AS population  
			FROM multi_isochrones m
			WHERE m.objectid = objectid_multi_isochrone 
		),
		iso_intersection AS (
			SELECT m.gid, s.name, ST_Intersection(s.geom,ST_SetSrid(m.geom,4326)) AS geom 
			FROM study_area s, multi_isochrones m
			WHERE s.name IN (SELECT UNNEST(region) AS name)
			AND m.objectid = objectid_multi_isochrone
		),
		reached_population AS (
			SELECT i.gid, i.name, jsonb_build_object(concat(i.name,'_reached'),round(sum(p.population)::integer,-1)) reached_population
			FROM iso_intersection i, population p  
			WHERE ST_intersects(i.geom, p.geom)
			GROUP BY i.gid, i.name
		)
		UPDATE multi_isochrones m
		SET population = x.new_population
		FROM (
			SELECT e.gid, array_to_json(array_agg(e.population|| r.reached_population)) new_population
			FROM expand_population e, reached_population r
			WHERE e.population::jsonb ? r.name
			AND e.gid = r.gid
			GROUP BY e.gid
		) x 
		WHERE m.gid = x.gid;
	
	ELSE 

		UPDATE multi_isochrones 
		SET population = population_mask || x.reached_population
		FROM (
			SELECT m.gid, jsonb_build_object('bounding_box_reached',round(sum(p.population)::integer,-1)) AS reached_population
			FROM population p, multi_isochrones m 
			WHERE ST_Intersects(p.geom,ST_Intersection(mask,ST_SetSrid(m.geom,4326)))
			AND m.objectid = objectid_multi_isochrone
			GROUP BY m.gid
		) x
		WHERE multi_isochrones.gid = x.gid;
	END IF; 
	RETURN query 
	SELECT gid,objectid, coordinates, userid,step, routing_profile, speed,alphashape_parameter,modus, parent_id, population, geom geometry 
	FROM multi_isochrones
	WHERE objectid = objectid_multi_isochrone;
	END;
$function$ LANGUAGE plpgsql;

/*
SELECT *
FROM pois_multi_isochrones(1,15,5.0,3,'walking_wheelchair',0.00003,'walking','study_area',ARRAY['16.3','16.4'],ARRAY['supermarket','bar']) ;

SELECT *
FROM pois_multi_isochrones(1,10,5.0,2,0.00003,'default','envelope',array['11.599198','48.130329','11.630676','48.113260'],array['supermarket','discount_supermarket']) 
--alphashape_parameter NUMERIC = 0.00003;
--region_type 'envelope' or study_area

SELECT *
FROM pois_multi_isochrones(1,15,5.0,3,'walking_wheelchair',0.00003,'walking','study_area',ARRAY['Hasenbergl-Lerchenau'],ARRAY['supermarket','bar']) ;
*/

