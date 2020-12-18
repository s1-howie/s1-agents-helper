#Requires -RunAsAdministrator
param(
    [Parameter(Position=0,mandatory=$true)]
    [string]$s1_console_prefix,
    [Parameter(Position=1,mandatory=$true)]
    [string]$api_key,
    [Parameter(Position=2,mandatory=$true)]
    [string]$site_token,
    [Parameter(Position=3,mandatory=$true)]
    [string]$version_status
    )

write-output "Console:          $s1_console_prefix"
write-output "API Key:          $api_key"
write-output "Site Token:       $site_token"
write-output "Version Status:   $version_status"


$s1_mgmt_url = "https://$s1_console_prefix.sentinelone.net"
Write-Output "mgmt url:         $s1_mgmt_url"
$api_endpoint = "/web/api/v2.1/update/agent/packages"
$agent_file_name = ""
$agent_download_link = ""

if (-Not ($api_key.Length -eq 80)) {
    Write-Output "API Keys are generally 80 characters long and are alphanumeric."
    exit 1
}

if (-Not ($site_token.Length -gt 100)) {
    Write-Output "Site Tokens are generally 100 characters or longer and are ASCII encoded."
    exit 1
}

if ($version_status -ne "GA" -and $version_status -ne "EA") {
    Write-Output "Invalid format for VERSION_STATUS: $version_status"
    Write-Output "The value of VERSION_STATUS must be either 'GA' or 'EA'"
    exit 1
}

Write-Output "all good"

$uri = $s1_mgmt_url + $api_endpoint
Write-Output $uri

# Configure HTTP header for API Calls
$apiHeaders = @{"Authorization"="APIToken $api_key"}
# The body contains parameters to search for packages with .exe file extensions.. ordering by latest version.
$body = @{
    "limit"=10
    "packageTypes"="Agent"
    "osTypes"="windows"
    "countOnly"="false"
    "sortBy"="createdAt"
    "fileExtension"=".exe"
    "sortOrder"="desc"
    }
# Query the S1 API
$response = Invoke-RestMethod -Uri $uri -Headers $apiHeaders -Method Get -ContentType "application/json" -Body $body
# Store the response data as a list of objects
$packages = $response.data

#Note: "$version_status*"" will match either GA or GA-SP1, GA-SP2, etc
foreach ($package in $packages) {
    if ($package.status -like "$version_status*") {
        $agent_download_link = $package.link
        $agent_file_name = $package.fileName
        break
    }
}

Write-Output "Agent File Name:     $agent_file_name"
Write-Output "Agent Download Link: $agent_download_link"

# Now that we have the download link and file name.  Download the package.
$wc = New-Object System.Net.WebClient
$wc.Headers['Authorization'] = "APIToken $api_key"
$wc.DownloadFile($agent_download_link, "$env:TEMP\$agent_file_name")
# Execute the package with the quiet option
& "$env:TEMP\$agent_file_name" /SITE_TOKEN=$site_token /quiet /reboot

