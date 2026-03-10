Get-Process | Where-Object { $_.Name -like '*yawcam*' -or $_.Name -like '*javaw*' } | Select-Object Name, Id
