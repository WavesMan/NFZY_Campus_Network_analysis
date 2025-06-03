<#
.SYNOPSIS
    Campus network auto-login script for PowerShell
.DESCRIPTION
    Automatically logs in to campus network with configurable credentials
    Version: 2.0
#>

# Logging functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "DEBUG"){"Gray"}else{"Green"})
    Add-Content -Path ".\campus_net.log" -Value $logMessage
}

# Load configuration
try {
    . .\campus_net_config.ps1
    Write-Log "Configuration loaded successfully"
}
catch {
    Write-Log "Error loading configuration: $_" -Level "ERROR"
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
    "User-Agent"               = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
}

# Check network connectivity
function Test-Network {
    $retryCount = 0
    $maxRetries = 10
    $retryDelay = 3
    
    while ($retryCount -lt $maxRetries) {
        try {
            if (Test-Connection -ComputerName 192.1.1.55 -Count 1 -Quiet) {
                Write-Log "Network connectivity confirmed"
                return $true
            }
        }
        catch {
            Write-Log "Network test failed (attempt $($retryCount+1)/$maxRetries)" -Level "DEBUG"
        }
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds $retryDelay
        }
    }
    Write-Log "Network connectivity check failed after $maxRetries attempts" -Level "ERROR"
    return $false
}

# Execute the login request with retries
$maxRetries = 3
$retryDelay = 5
$attempt = 1
$success = $false

if (Test-Network) {
    while ($attempt -le $maxRetries -and -not $success) {
        Write-Log "Attempting login (try $attempt of $maxRetries)"
        
        try {
            $response = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop
            $responseContent = $response.Content
            Write-Log "Login successful! Status code: $($response.StatusCode)"
            Write-Log "Response length: $($responseContent.Length) chars"
            if ($Config.LogLevel -eq "DEBUG") {
                # Save full response to separate file
                $responseFile = ".\login_response_$(Get-Date -Format 'yyyyMMddHHmmss').html"
                $responseContent | Out-File -FilePath $responseFile
                Write-Log "Full response saved to: $responseFile" -Level "DEBUG"
                # Also log first 200 chars for quick reference
                $preview = $responseContent.Substring(0, [Math]::Min(200, $responseContent.Length))
                Write-Log "Response preview: $preview..." -Level "DEBUG"
            }
            $success = $true
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            $errorMsg = $_.Exception.Message
            $responseContent = if($_.Exception.Response) { 
                (New-Object System.IO.StreamReader $_.Exception.Response.GetResponseStream()).ReadToEnd() 
            } else { "" }
            
            Write-Log "Login failed (attempt $attempt): Status $statusCode, Error: $errorMsg" -Level "ERROR"
            if ($Config.LogLevel -eq "DEBUG") {
                # Save full error response to separate file
                $errorFile = ".\login_error_$(Get-Date -Format 'yyyyMMddHHmmss').html"
                $responseContent | Out-File -FilePath $errorFile
                Write-Log "Full error response saved to: $errorFile" -Level "DEBUG"
                # Also log first 200 chars for quick reference
                $preview = $responseContent.Substring(0, [Math]::Min(200, $responseContent.Length))
                Write-Log "Error preview: $preview..." -Level "DEBUG"
            }
            
            $attempt++
            if ($attempt -le $maxRetries) {
                Write-Log "Waiting $retryDelay seconds before next attempt..."
                Start-Sleep -Seconds $retryDelay
            }
        }
    }
}

if (-not $success) {
    Write-Log "All login attempts failed" -Level "ERROR"
    exit 1
}
