#Find-Module -Name SqlServer | Install-Module -AllowClobber

Import-Module SqlServer 

$dba_main = 'localhost'

$restoreRoot = '\\someShare\withAlot\ofSpace'
if (!(Test-Path $restoreRoot)) {
        New-Item -ItemType Directory -Path $restoreRoot
    }

Invoke-Sqlcmd -ServerInstance $dba_main -Database 'DBA' -Query 'exec [dbo].[usp_db_restore_validation_create_tables]'

$fetch_rs = Invoke-Sqlcmd -ServerInstance $dba_main -Database 'DBA' -Query 'exec [dbo].[usp_fetch_production_registered_servers]'

foreach ($rs in $fetch_rs) { 
    $sqlcon = 'SQLSERVER:\SQL\' + $rs.server_name + '\' + $rs.instance_name + ''
    $sqlserver = Get-Item $sqlcon

    $restoreLoc = $restoreRoot + $sqlserver.Name + '\'
    $dbs = $sqlserver.Databases

    #  loop through the databases on the server
    foreach ($d in $dbs | Where {$_.Name -ne 'master' -and  $_.Name -ne 'model' -and $_.Name -ne 'msdb' -and $_.Name -notlike '*tempdb*'}) { 
    
        $q_history = '
        if (select count(*) from [linked_server_cms].dba.dbo.db_restore_validation_history where database_name = ''' + $d.Name + ''' having count(*) = 0) = 0
        begin
	        select ''1'' as [execute_flag]
        end
        else if (
	        select top 1 ''1'' as [execute_flag]
	        from [linked_server_cms].dba.dbo.db_restore_validation_history 
	        where 
		        database_name = ''' + $d.Name + ''' and 
		        convert(date, getdate(), 103) >=  (select max(dateadd(d, 30, restore_datetime)) from [linked_server_cms].dba.dbo.db_restore_validation_history where database_name = ''' + $d.Name + ''')
	        order by restore_datetime desc
        ) = ''1''
        begin
	        select ''1'' as [execute_flag]
        end
        '
        $history_limit = Invoke-Sqlcmd -ServerInstance $dba_main -Query $q_history

        #  begin 'execute_flag' iff statement for the inner most loop (e.g., if the flag is 0 no work to do)
        if ($history_limit.execute_flag -eq '1') {
    
             #  create and populate table for storing restore validation logic
            $build = '
            if object_id(''z.backupMediaSet'') is null
            begin
                create table z.backupMediaSet (
	                server_name sysname,
	                database_name sysname,
	                database_id int,
	                backup_start_date datetime,
	                backup_finish_date datetime,
                    backup_size_gb float,
	                physical_device_name varchar(1000)
                )
            end

            insert into z.backupMediaSet 
            select top 1 
                bs.server_name, bs.database_name, d.database_id, bs.backup_start_date, bs.backup_finish_date, 
                cast((bs.backup_size  / 1073741824) as float) as backup_size_gb, bm.physical_device_name
            from msdb.dbo.backupmediafamily bm
            inner join msdb.dbo.backupset bs ON bs.media_set_id = bm.media_set_id
            inner join sys.databases d on d.name=bs.database_name
            where 
                bs.database_name = ''' + $d.Name + ''' and 
                bs.[type] = ''D'' and
                bs.is_copy_only = 0 and (
                    bm.physical_device_name like ''\\%'' or
                    bm.physical_device_name like ''[A-Z]:%''
                )
            order by bm.media_set_id desc
            '
            $q = Invoke-Sqlcmd -ServerInstance $sqlserver.Name -Database 'DBA' -Query $build

            $fetch = '
            select z.server_name, z.database_name, z.database_id, z.backup_start_date, z.backup_finish_date, z.physical_device_name, z.backup_size_gb
            from z.backupMediaSet z
            where z.database_name = ''' + $d.Name + '''
            '
            $q = Invoke-Sqlcmd -ServerInstance $sqlserver.Name -Database 'DBA' -Query $fetch

            #  set variables based upon fetch result(s)
            $sName = $q.server_name
            $dbName = $q.database_name
            $dbName_restore = 'v_' + $sName + '_' + $q.database_name
            $b_start = $q.backup_start_date
            $b_end = $q.backup_finish_date
            $b_device = $q.physical_device_name
            [float]$b_size = $q.backup_size_gb

            #  create ...\ROWS if not exists
            $re_rows_dir = ($restoreLoc + $d.Name + '\ROWS')        
            if (!(Test-Path $re_rows_dir)) {
                New-Item -ItemType Directory -Path $re_rows_dir
            }

            #  set ROWS related variables 
            $fetch_rows = '
            select [name], 
            case 
	            when physical_name like ''%.mdf%'' then ''.mdf''
	            when physical_name like ''%.ndf%'' then ''.ndf''
            end as [ext]
            from sys.master_files f
            inner join z.backupMediaSet b on b.database_id=f.database_id
            where type_desc = ''ROWS''
            '
            $q_rows = Invoke-Sqlcmd -ServerInstance $sqlserver.Name -Database 'DBA' -Query $fetch_rows

            #  build array of logical file names to physical path
            $rows_file_name = ''
            $rows_file_dir = ''
            foreach ($q_row in $q_rows) {
                    $rows_file_name += @($q_row.name)
                    $rows_file_dir += @($re_rows_dir + '\' + $q_row.name + $q_row.ext)
            }
        
            #  set SMORF variables [logical file name > physical path]
            for($i=1; $i -lt $rows_file_name.Count; $i++) {
                $SMORF = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($rows_file_name[$i], $rows_file_dir[$i])
                New-Variable -Name "SMORF_$i" -Value $SMORF -Force            
            }
        
            #  create ...\LOG if not exists
            $re_log_dir = ($restoreLoc + $d.Name + '\LOG')
            if (!(Test-Path $re_log_dir)) {
                New-Item -ItemType Directory -Path $re_log_dir
            }

            #  set LOG related variables
            $fetch_log = '
            select [name], ''.ldf'' as [ext]
            from sys.master_files f
            inner join z.backupMediaSet b on b.database_id=f.database_id
            where type_desc = ''LOG''
            '
            $q_log = Invoke-Sqlcmd -ServerInstance $sqlserver.Name -Database 'DBA' -Query $fetch_log

            $log_file_name = $q_log.name
            $log_file_dir = ($re_log_dir + '\' + $log_file_name + $q_log.ext)

            $re_log = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($log_file_name, $log_file_dir)
            
            #[datetime]$today = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
            [datetime]$today = Get-Date -UFormat '%m, %d, %y'
            if ($b_size -gt 50) {
                $r_insert = '
                exec dbo.usp_db_restore_validation_ex_insert
                @server_name = ''' + $sqlserver.Name + ''', 
                @database_name = ''' + $d.Name + ''', 
                @backup_start = ''' + $q.backup_start_date + ''', 
                @backup_finish = ''' + $q.backup_finish_date + ''',
                @backup_location = ''' + $q.physical_device_name + ''', 
                @backup_size_gb = ' + $b_size + ',
                @ex_datetime = ''' + $today + ''',  
                @ex_reason = ''backup_size too large for automation restore''
                '
                Invoke-Sqlcmd -ServerInstance $dba_main -Database 'DBA' -Query $r_insert

            } else {
                      
                try { 
                    Write-Output ('Attempting restore for ' + $sqlserver.Name + ' --> ' + $d.Name)

                    #[datetime]$today = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
                    $restore_start = Get-Date

                    Restore-SqlDatabase -ServerInstance $dba_main -Database $dbName_restore -BackupFile $b_device -ReplaceDatabase -RelocateFile @(for($c=1;$c -lt $i;$c++){Get-Variable "SMORF_$c" -ValueOnly}, $re_log) 
                    $restore_finish = Get-Date
                    $restore_minutes = (New-TimeSpan -Start $restore_start -End $restore_finish).Minutes

                    $r_insert = '
                    exec dbo.usp_db_restore_validation_insert
                    @server_name = ''' + $sqlserver.Name + ''', 
                    @database_name = ''' + $d.Name + ''', 
                    @backup_start = ''' + $q.backup_start_date + ''', 
                    @backup_finish = ''' + $q.backup_finish_date + ''',
                    @backup_location = ''' + $q.physical_device_name + ''', 
                    @backup_size_gb = ' + $b_size + ',
                    @restore_minutes = ''' + $restore_minutes + ''', 
                    @restore_datetime = ''' + $today + ''',  
                    @restore_location = ''' + $restoreLoc + $d.Name + ''',
                    @is_valid = 1
                    '
                    Invoke-Sqlcmd -ServerInstance $dba_main -Database 'DBA' -Query $r_insert

                    $d = 'drop database [' + $dbName_restore + '];' 
                    Invoke-SqlCmd -ServerInstance $dba_main -Query $d
                }
                catch { #  nothing but qq up in here
                    $r_insert = '
                    exec dbo.usp_db_restore_validation_insert
                    @server_name = ''' + $sqlserver.Name + ''', 
                    @database_name = ''' + $d.Name + ''', 
                    @backup_start = ''' + $q.backup_start_date + ''', 
                    @backup_finish = ''' + $q.backup_finish_date + ''',
                    @backup_location = ''' + $q.physical_device_name + ''', 
                    @backup_size_gb = ' + $b_size + ',
                    @restore_minutes = ''' + $restore_minutes + ''', 
                    @restore_datetime = ''' + $today + ''',  
                    @restore_location = ''' + $restoreLoc + $d.Name + ''',
                    @is_valid = 0
                    '
                    Invoke-Sqlcmd -ServerInstance $dba_main -Database 'DBA' -Query $r_insert
                }        
            }
        }
    }
}
