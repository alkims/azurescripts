Configuration alkimsSQLServer
{
    $credential = Get-AutomationPSCredential -Name "SQLLocalAdmin"
    Node "SQLSERVER" 
    {
        Script ConfigureSql
        {
            TestScript = {
                return $false
            }
            SetScript = {
                
		        $disks = Get-Disk | Where partitionstyle -eq 'raw' 
		        if($disks -ne $null)
		        {
		            # Create a new storage pool using all available disks 
		            New-StoragePool -FriendlyName "VMStoragePool" `
				            -StorageSubsystemFriendlyName "Windows Storage*" `
				            -PhysicalDisks (Get-PhysicalDisk -CanPool $True)

		            # Return all disks in the new pool
		            $disks = Get-StoragePool -FriendlyName "VMStoragePool" `
					            -IsPrimordial $false | 
					            Get-PhysicalDisk

		            # Create a new virtual disk 
		            New-VirtualDisk -FriendlyName "DataDisk" `
				            -ResiliencySettingName Simple `
						            -NumberOfColumns $disks.Count `
						            -UseMaximumSize -Interleave 256KB `
						            -StoragePoolFriendlyName "VMStoragePool" 

		            # Format the disk using NTFS and mount it as the F: drive
		            Get-Disk | 
			            Where partitionstyle -eq 'raw' |
			            Initialize-Disk -PartitionStyle MBR -PassThru |
			            New-Partition -DriveLetter "F" -UseMaximumSize |
	                    Format-Volume -FileSystem NTFS -NewFileSystemLabel "DataDisk" -Force
                }

      		    $logs = "F:\Logs"
		        $data = "F:\Data"
		        $backups = "F:\Backup" 
		        [system.io.directory]::CreateDirectory($logs)
		        [system.io.directory]::CreateDirectory($data)
		        [system.io.directory]::CreateDirectory($backups)
		        [system.io.directory]::CreateDirectory("C:\SQDATA")

	            # Setup the data, backup and log directories as well as mixed mode authentication
	            Import-Module "sqlps" -DisableNameChecking
	            [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	            $sqlesq = new-object ('Microsoft.SqlServer.Management.Smo.Server') Localhost
	            $sqlesq.Settings.LoginMode = [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed
	            $sqlesq.Settings.DefaultFile = $data
	            $sqlesq.Settings.DefaultLog = $logs
	            $sqlesq.Settings.BackupDirectory = $backups
	            $sqlesq.Alter() 

	            # Restart the SQL Server service
	            Restart-Service -Name "MSSQLSERVER" -Force

	            # Re-enable the sa account and set a new password to enable login
	            Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "ALTER LOGIN sa ENABLE"
	            Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "ALTER LOGIN sa WITH PASSWORD = 'demo@pass123'"


	            # Get the Adventure works database backup 
	            $dbsource = "https://cloudworkshop.blob.core.windows.net/arm-hackathon/AdventureWorks2012.bak"
	            $dbdestination = "C:\SQDATA\AdventureWorks2012.bak"
	            Invoke-WebRequest $dbsource -OutFile $dbdestination 

                $mdf = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile, Microsoft.SqlServer.SmoExtended, Version=13.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91' -ArgumentList "AdventureWorks2012_Data", "F:\Data\AdventureWorks2012.mdf"
                $ldf = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile, Microsoft.SqlServer.SmoExtended, Version=13.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91' -ArgumentList "AdventureWorks2012_Log", "F:\Logs\AdventureWorks2012.ldf"


	            # Restore the database from the backup
	            Restore-SqlDatabase -ServerInstance Localhost -Database AdventureWorks `
					            -BackupFile $dbdestination -RelocateFile @($mdf,$ldf)  
                    

	            New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action allow 
                
	        }
  
            GetScript = {
                @{Result = "ConfigureSql"}
            }

            PsDscRunAsCredential = $credential

        }
    }
}
