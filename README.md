# SqlServer-RestoreValidation
Crawls over a CMS and dynamically restores the most FULL backup for validity.

All restores (non-system databases) are performed on the CMS server with a prefix and their files are relocated to a \\\share. 

The history table works by either attempting a restore on a newly found backup set or a backup set which hasn't been restored in thirty days.

The exception table is for capturing any database which its FULL backup is > 50GB as the network was choking; nothing more. Silly infrastructure. 

The CATCH for the any restore failures isn't handled the best and is merely a flat out CATCH.

Unfortunately, I was unable to automate the process to alert at discretion. =\

NOTE: I manually created the 'z' schema in the 'DBA' database on every server (which GRANT EXECUTE to [public]) which is listed in the CMS as I was unable to figure out a decent way of handling passing params to/from each query in PoSH. If I had the time I would have refactored the creation in the PoSH or figured out another solution which didn't require such a schema at all. =\
