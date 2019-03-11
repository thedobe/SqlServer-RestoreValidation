# SqlServer-RestoreValidation
Crawls over a CMS and dynamically restores the most FULL backup for validity

NOTE: I manually created the 'z' schema in the 'DBA' database on every server (which GRANT EXECUTE to [public]) which is listed in the CMS as I was unable to figure out a decent way of handling passing params to/from each query in PoSH. If I had the time I would have refactored the creation in the PoSH or figured out another solution which didn't require such a schema at all. =\
