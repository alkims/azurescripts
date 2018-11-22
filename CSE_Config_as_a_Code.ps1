Install-WindowsFeature web-server -IncludeManagementTools
#do more stuff
Start-Process -FilePath C:\Windows\System32\Sysprep\Sysprep.exe -ArgumentList '/generalize /oobe /shutdown /quiet'
