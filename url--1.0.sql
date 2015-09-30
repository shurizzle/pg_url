\echo Use "CREATE EXTENSION url_encode" to load this file. \quit

CREATE OR REPLACE FUNCTION url_encode(TEXT)
RETURNS TEXT
AS $$
SELECT COALESCE(string_agg(CONCAT(t.x,regexp_replace(upper(encode(convert_to(t.y,'utf8'),'hex')),'(..)',E'%\\1','g')),''),$1)
FROM UNNEST(regexp_split_to_array($1, E'[^0-9A-Za-z\\.\\-~_]+'), ARRAY(SELECT (regexp_matches($1, E'[^0-9A-Za-z\\.\\-~_]+', 'g'))[1])) AS t(x, y);
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION url_decode(TEXT)
RETURNS TEXT
AS $$
SELECT COALESCE(string_agg(CONCAT(t.x,convert_from(decode(replace(t.y,'%',''),'hex'),'utf8')),''),$1)
FROM UNNEST(regexp_split_to_array($1, '(%[0-9a-fA-F][0-9a-fA-F])+'), ARRAY(SELECT (regexp_matches($1, '((?:%[0-9a-fA-F][0-9a-fA-F])+)', 'g'))[1])) AS t(x, y);
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE TYPE kventry AS (
	key TEXT,
	value TEXT
);

CREATE TYPE qskv AS (
	entries kventry[]
);

CREATE OR REPLACE FUNCTION qs_to_qskv(TEXT)
RETURNS qskv
AS $$
DECLARE
	p INTEGER;
	kv TEXT;
	res kventry[];
BEGIN
	FOREACH kv IN ARRAY string_to_array($1, '&')
	LOOP
		p := strpos(kv, '=');
		res := res ||
		CASE WHEN p < 1 THEN ROW(kv, NULL)::kventry
		                ELSE ROW(substr(kv, 1, p - 1), NULLIF(url_decode(substr(kv, p + 1)), ''))::kventry
		END;
	END LOOP;

	RETURN ROW(res)::qskv;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION UNNEST(qskv)
RETURNS TABLE (key TEXT, value TEXT)
AS $$
SELECT *
FROM UNNEST($1.entries);
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION qskv_to_qs(qskv)
RETURNS TEXT
AS $$
SELECT string_agg(CASE WHEN NULLIF(value,'') IS NULL THEN key ELSE key || '=' || url_encode(value) END, '&')
FROM UNNEST($1);
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION qskv(TEXT)
RETURNS qskv
AS $$
SELECT qs_to_qskv($1);
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE CAST (TEXT AS qskv) WITH FUNCTION qs_to_qskv(TEXT);
CREATE CAST (qskv AS TEXT) WITH FUNCTION qskv_to_qs(qskv);

CREATE TYPE url AS (
	scheme TEXT,
	authority TEXT,
	domain TEXT,
	port INTEGER,
	path TEXT,
	querystring qskv,
	fragment TEXT
);

CREATE OR REPLACE FUNCTION url(TEXT)
RETURNS url
AS $$
DECLARE
	p TEXT[] := regexp_matches($1, E'^(?:([^:/?#]+):)?(?://(?:((?:%\h\h|[!$&-.0-;=A-Z_a-z~])*)@)?([^/?#]+?)(?::([0-9]+))?)?([^?#]*)(?:\\?([^#]*))?(?:#(.*))?', 'i');
BEGIN
	RETURN ROW(p[1], p[2], p[3], NULLIF(p[4],'')::INTEGER, p[5], p[6], p[7])::url;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;
