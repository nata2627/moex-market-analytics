-- staging.security_raw -> core.security
--
-- Справочник описывает текущее состояние бумаги, поэтому ON CONFLICT
-- DO UPDATE безусловный. Для котировок логика обратная, см. 15_quote.sql.
INSERT INTO core.security (secid, shortname, secname, isin, lotsize, issuesize, listlevel, sectype)
SELECT DISTINCT ON (secid)
       secid,
       shortname,
       secname,
       NULLIF(btrim(isin), ''),
       NULLIF(btrim(lotsize),   '')::integer,
       NULLIF(btrim(issuesize), '')::bigint,
       NULLIF(btrim(listlevel), '')::smallint,
       NULLIF(btrim(sectype),   '')
  FROM staging.security_raw
 WHERE _batch_id = %(batch_id)s
   AND secid IS NOT NULL
   AND shortname IS NOT NULL
 -- DISTINCT ON защищает от ошибки "ON CONFLICT DO UPDATE command cannot
 -- affect row a second time", если API отдаст бумагу дважды.
 ORDER BY secid, _loaded_at DESC
    ON CONFLICT (secid) DO UPDATE
   SET shortname  = EXCLUDED.shortname,
       secname    = EXCLUDED.secname,
       isin       = EXCLUDED.isin,
       lotsize    = EXCLUDED.lotsize,
       issuesize  = EXCLUDED.issuesize,
       listlevel  = EXCLUDED.listlevel,
       sectype    = EXCLUDED.sectype,
       updated_at = now();
