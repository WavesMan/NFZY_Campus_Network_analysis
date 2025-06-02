<#
.SYNOPSIS
    Campus network auto-login script for PowerShell
.DESCRIPTION
    Automatically logs in to campus network with configurable credentials
#>

# Load configuration
try {
    . .\campus_net_config.ps1
    Write-Host "Configuration loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Error loading configuration: $_" -ForegroundColor Red
    exit 1
}

# Prepare request parameters
$uri = $Config.PortalUrl + "?c=ACSetting&a=Login&protocol=http:&hostname=192.1.1.55&iTermType=0" +
       "&wlanuserip=$($Config.WlanUserIp)&wlanacip=null&wlanacname=null&mac=$($Config.MacAddress)" +
       "&ip=0.0.0.0&enAdvert=0&queryACIP=0&jsVersion=2.4.3&loginMethod=1"

$body = @{
    DDDDD    = ",0,$($Config.Username)"
    upass    = $Config.Password
    R1       = "0"
    R2       = "0"
    R3       = "0"
    R6       = "0"
    para     = "00"
    '0MKKey' = "123456"
}

$headers = @{
    "Accept"                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Encoding"           = "gzip, deflate"
    "Accept-Language"           = "zh-CN,zh;q=0.9,en;q=0.8"
    "Cache-Control"             = "max-age=0"
    "Content-Type"             = "application/x-www-form-urlencoded"
    "Host"                     = "192.1.1.55:801"
    "Origin"                   = "http://192.1.1.55"
    "Referer"                  = "http://192.1.1.55/"
    "Upgrade-Insecure-Requests" = "1"
    "User-Agent"               = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
}

# Execute the login request
try {
    $response = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body
    Write-Host "Login successful! Status code:" $response.StatusCode -ForegroundColor Green
}
catch {
    Write-Host "Login failed:" $_.Exception.Message -ForegroundColor Red
}
