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

CREATE OR REPLACE FUNCTION UNNEST(qskv)
RETURNS TABLE (key TEXT, value TEXT)
AS $$
SELECT *
FROM UNNEST($1.entries);
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION string_to_kventry(TEXT)
RETURNS kventry
AS $$
DECLARE
	p INTEGER := strpos($1, '=');
BEGIN
	RETURN CASE WHEN p < 1 THEN ROW($1, NULL)::kventry
	            ELSE            ROW(substr($1, 1, p - 1), NULLIF(url_decode(substr($1, p + 1)), ''))::kventry
	       END;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION kventry(TEXT)
RETURNS kventry
AS $$
SELECT string_to_kventry($1);
$$
LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION kventry_to_string(kventry)
RETURNS TEXT
AS $$
SELECT CASE WHEN NULLIF($1.value,'') IS NULL THEN $1.key
            ELSE                                  $1.key || '=' || url_encode($1.value)
       END;
$$
LANGUAGE sql;

CREATE CAST (TEXT AS kventry) WITH FUNCTION string_to_kventry(TEXT);
CREATE CAST (kventry AS TEXT) WITH FUNCTION kventry_to_string(kventry);

CREATE OR REPLACE FUNCTION string_to_qskv(TEXT)
RETURNS qskv
AS $$
SELECT ROW((
	SELECT array_agg(v::kventry)
	FROM UNNEST(string_to_array($1, '&')) t(v)
	))::qskv;
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION qskv_to_string(qskv)
RETURNS TEXT
AS $$
SELECT string_agg(kventry_to_string(t),'&')
FROM UNNEST($1) t;
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION qskv(TEXT)
RETURNS qskv
AS $$
SELECT string_to_qskv($1);
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE CAST (TEXT AS qskv) WITH FUNCTION string_to_qskv(TEXT);
CREATE CAST (qskv AS TEXT) WITH FUNCTION qskv_to_string(qskv);

CREATE TYPE url AS (
	scheme TEXT,
	authority TEXT,
	domain TEXT,
	port INTEGER,
	path TEXT,
	querystring qskv,
	fragment TEXT
);

CREATE OR REPLACE FUNCTION string_to_url(TEXT)
RETURNS url
AS $$
DECLARE
	p TEXT[] := regexp_matches($1, E'^(?:([^:/?#]+)://)?(?:(?:((?:%\h\h|[!$&-.0-;=A-Z_a-z~])*)@)?([^/?#]+?)(?::([0-9]+))?)?([^?#]*)(?:\\?([^#]*))?(?:#(.*))?$', 'i');
BEGIN
	RETURN ROW(p[1], p[2], p[3], NULLIF(p[4],'')::INTEGER, p[5], p[6], p[7])::url;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION url(TEXT)
RETURNS url
AS $$
SELECT string_to_url($1);
$$
LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION url_to_string(url)
RETURNS TEXT
AS $$
SELECT NULLIF(CONCAT($1.scheme || '://', $1.authority || '@', $1.domain, ':' || $1.port, $1.path, '?' || qskv_to_string($1.querystring), '#' || $1.fragment),'');
$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE CAST (TEXT AS url) WITH FUNCTION string_to_url(TEXT);
CREATE CAST (url AS TEXT) WITH FUNCTION url_to_string(url);
