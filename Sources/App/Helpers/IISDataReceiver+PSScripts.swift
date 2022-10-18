//
//  IISDataReceiver+PSScripts.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import Foundation

extension IISDataReceiver {
    static var execQueryScript = ###"""
        # Script parameters:
        # - $logsPath: [String]
        # - $startDate: [datetime]?
        # - $endDate: [datetime]?
        # - $query: [String]

        Function Get-IISLogFilesByDate {
            param (
                [Parameter(Mandatory)]
                [string]$LogsDirectory,

                [Parameter(Mandatory = $false)]
                [datetime]$StartTime,
            
                [Parameter(Mandatory = $false)]
                [datetime]$EndTime
            )
            PROCESS
            {
                foreach ($filePath in (Get-ChildItem -Path $LogsDirectory).FullName) {
                    $dateRegexPattern = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
                    $fileStartTime = Get-Content -Path $filePath -First 5 | Select-Object -Last 1 | Where-Object { $_ -match $dateRegexPattern} | ForEach-Object { [datetime]$Matches[0] }
                    $fileEndTime = Get-Content -Path $filePath -Last 1 | Select-Object -Last 1 | Where-Object { $_ -match $dateRegexPattern } | ForEach-Object { [datetime]$Matches[0] }
                   
                    if (($null -ne $StartTime) -and ($null -ne $EndTime)) {
                        if (($StartTime -le $fileEndTime) -and ($EndTime -ge $fileStartTime)) {
                            $filePath
                        }
                        continue
                    }

                    if ($null -ne $StartTime) {
                        if ($StartTime -le $fileEndTime) {
                            $filePath
                        }
                        continue
                    }

                    if ($null -ne $EndTime) {
                        if ($EndTime -ge $fileStartTime) {
                            $filePath
                        }
                    }
                }
            }
        }

        if ($null -eq $endDate) { $endDate = [datetime](Get-Date).AddHours(-3) } # today
        if ($null -eq $startDate) { $startDate = $endDate.Date.DateTime -as [datetime] } # Same as endDate, but at 00:00:00
        if ($startDate -eq $endDate) { $endDate= $endDate.AddDays(1) -as [datetime] } # All day for specified date

        $serverTimeZone = +3 # affects to difference between system time and time in stored IIS logs
        $startDate = $startDate.AddHours(-$serverTimeZone)
        $endDate = $endDate.AddHours(-$serverTimeZone)

        $logFiles = (Get-IISLogFilesByDate -LogsDirectory $logsPath -StartTime $startDate -EndTime $endDate| Foreach-Object {"'$_'"} ) -join ','
        $query = $query -replace '#logFiles#', $logFiles

        if ($logFiles.Length -eq 0) { exit }

        $query = $query -replace '#dateFilter#', @"
        (
            STRCAT(TO_STRING(date,'yyyy-MM-dd '),TO_STRING(time,'hh:mm:ss')) >= '$($startDate.ToString("yyyy-MM-dd HH:mm:ss"))'
            AND STRCAT(TO_STRING(date,'yyyy-MM-dd '),TO_STRING(time,'hh:mm:ss')) <= '$($endDate.ToString("yyyy-MM-dd HH:mm:ss"))'
        )

        "@

        $query = $query -replace  '#excludeInternalIPs#', @"
        (
            NOT c-ip LIKE '%:%'
            AND NOT c-ip LIKE '10.%'
            AND NOT c-ip LIKE '127%'
            AND NOT c-ip LIKE '169.254%'
            AND NOT c-ip LIKE '172.16.%'
            AND NOT c-ip LIKE '172.17.%'
            AND NOT c-ip LIKE '172.18.%'
            AND NOT c-ip LIKE '172.19.%'
            AND NOT c-ip LIKE '172.2_.%'
            AND NOT c-ip LIKE '172.30%'
            AND NOT c-ip LIKE '172.31%'
            AND NOT c-ip LIKE '192.168.%'
        )

        "@

        $query = $query -replace '#userType=authenticated#', @"
        (
            cs-username IS NOT NULL
        )

        "@

        $query = $query -replace '#userType=anonymous#', @"
        (
            cs-username IS NULL
        )

        "@

        $parser = New-Object -ComObject "MSUtil.LogQuery"
        $parserInputFormat = New-Object -ComObject "MSUtil.LogQuery.W3CInputFormat"

        $parserResults = $parser.Execute($query, $parserInputFormat)

        $record = $null
        while (-not $parserResults.atEnd()) {
            $record = $parserResults.getRecord()
            $record.toNativeString(" ")
            $parserResults.moveNext()
        }
        """###
}


