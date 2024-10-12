Function Install-Php {
    Param(
        [String] $Version = '',
        [String[]] $Extensions = @(),
        [String] $Path = [Environment]::GetFolderPath('ApplicationData') + '\Php'
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    If (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Force -Recurse | Out-Null
    }
    New-Item -ItemType Directory -Path $Path | Out-Null
    $Architecture = If ([System.Environment]::Is64BitOperatingSystem) { '-x64' } Else { '-x86' }
    $UriBase = 'https://windows.php.net'
    $Response = Invoke-WebRequest -UseBasicParsing -Uri ($UriBase + '/download')
    $PathDownload = ($Response.Links | Where-Object -Property 'Href' -Match "downloads/releases/(php-$Version[\d.]*-Win32-\w{4}$Architecture.zip)" | Select-Object -First 1).Href
    If (-Not $Matches[0]) {
        Write-Error -Message 'PHP version was not found'
    }
    $FileZip = $Matches[1]
    $PathFileZip = ([System.IO.Path]::GetTempPath() + $FileZip)
    Invoke-WebRequest -UseBasicParsing ($UriBase + $PathDownload) -OutFile $PathFileZip
    Expand-Archive -Path $PathFileZip -DestinationPath $Path
    Remove-Item -Path $PathFileZip
    ForEach ($Target in 'User', 'Process') {
        $EnvPaths = [System.Environment]::GetEnvironmentVariable('Path', $Target).Split(';')
        If ($EnvPaths -NotContains $Path) {
            [System.Environment]::SetEnvironmentVariable('Path', (($EnvPaths + $Path) -Join ';'), $Target)
        }
    }
    Set-PhpExtensions -Names $Extensions
}
Function Uninstall-Php {
    Param(
        [String] $Path = [Environment]::GetFolderPath('ApplicationData') + '\Php'
    )
    Remove-Item -Path $Path -Force -Recurse
    ForEach ($Target in 'User', 'Process') {
        $EnvPaths = ([System.Environment]::GetEnvironmentVariable('Path', $Target)).Split(';')
        [System.Environment]::SetEnvironmentVariable('Path', (($EnvPaths | Where-Object { $_ -Ne $Path }) -Join ';'), $Target)
    }
}
Function Set-PhpExtensions {
    Param(
        [String[]] $Names = @()
    )
    $Php = Get-Command -Name php -ErrorAction Stop
    $Path = Split-Path -Path $Php.Source
    $PathFileIni = $Path + '\php.ini'
    If (Test-Path -Path $PathFileIni) {
        $Config = [String] (Get-Content -Path $PathFileIni | Select-String -Pattern 'zend_extension\s*=|extension\s*=|xdebug.' -NotMatch)
    }
    Else {
        $Config = ''
    }
    ForEach ($Name in $Names) {
        If ($Name -eq 'xdebug') {
            $Architecture = If ([System.Environment]::Is64BitOperatingSystem) { '-x86_64' } Else { '' }
            $VersionPhpMinor = [String]$Php.Version.Major + '.' + [String]$Php.Version.Minor
            $UriBase = 'http://xdebug.org'
            $Response = Invoke-WebRequest -UseBasicParsing -Uri ($UriBase + '/download/historical')
            $PathDownload = ($Response.Links | Where-Object -Property 'Href' -Match "files/(php_xdebug-([\d.]+)-$VersionPhpMinor-\w{4}$Architecture.dll)" | Select-Object -First 1).Href
            IF (-Not $Matches[0]) {
                Write-Error -Message 'Xdebug for this version of PHP was not found'
            }
            $PathFileXdebug = $Path + '\ext\' + [String]$Matches[1]
            Invoke-WebRequest -UseBasicParsing ($UriBase + '/' + $PathDownload) -OutFile $PathFileXdebug
            $Config += "`nzend_extension = `"$PathFileXdebug`""
            If ($Matches[0] -lt 3) {
                $Config += "`nxdebug.remote_enable = on`nxdebug.remote_autostart = on"
            }
            Else {
                $Config += "`nxdebug.mode = debug`nxdebug.start_with_request = yes"
            }
        }
        Else {
            If (Test-Path -Path "$Path\ext\php_$Name.dll") {
                $Config += "`nextension = `"$Path\ext\php_$Name.dll`""
            }
        }
    }
    Set-Content -Path $PathFileIni -Value $Config
}
Function Get-PhpExtensions {
    $Php = Get-Command -Name php -ErrorAction Stop
    $Path = Split-Path -Path $Php.Source
    $PathFileIni = $Path + '\php.ini'
    (Get-Content -Path $PathFileIni | Select-String -Pattern '(zend_extension|extension)\s*=.*php_(\w+)').Matches |
    ForEach-Object {
        If ($_.Groups) {
            Write-Output $_.Groups[2].Value
        }
    }
}