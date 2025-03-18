[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [String]$apiKey,
  
  [Parameter(Mandatory=$true)]
  [String]$userName,
  
  [Parameter(Mandatory=$true)]
  [Security.SecureString]$securePassword=$(Throw "Password required.")
)


function Send-API-POST-Request
{
    param(
        $formData,
        $URI,
        $apiKey
    )
    
    #$form = @{"name" = "Testsvr3"}
    #$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    #$fileEnc = [System.Text.Encoding]::GetEncoding('UTF-8').GetString($fileBytes)
    #$formData = "name=Testsvr3"
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $formDataKeys = ""
    $formDataValues = ""

    #$formData.PSObject.Properties | ForEach-Object {
    #    $formDataParsed += -join($_.Name, "=", $_.Value, $LF)
    #}
    # foreach ($h in $formData.Keys)
    # {
        # $formDataKeys += "$($h)=`"$($h)`"; "
        # $formDataValues += -join($formData.$h, $LF)
    # }
    
    $bodyLines = ""
    foreach ($h in $formData.Keys)
    {
        $bodyLines += "--$boundary$($LF)"
        #$bodyLines += "Content-Disposition: form-data; $($h)=`"$($formData.$h)`"$($LF)$($LF)"
        $bodyLines += "Content-Disposition: form-data; name=`"$($h)`"$($LF)$($LF)"
        $bodyLines += "$($formData.$h)$($LF)"
    }
    $bodyLines += "--$boundary--$LF" 
    
    # $bodyLines = ( 
    # "--$boundary",
    # "Content-Disposition: form-data; $($formDataKeys)",
    # $formDataValues,
    # "--$boundary--$LF" 
    # ) -join $LF
    
    try 
    {
        $response = Invoke-WebRequest -Uri $URI -UseBasicParsing -Method "POST" `
        -ContentType "multipart/form-data; boundary=`"$boundary`"" `
        -Headers @{'Authorization' = -join('Bearer ', $apiKey)} `
        -Body $bodyLines
        
        $response
    }
    catch
    {
        echo $formDataParsed
    }
}

$hostname = hostname
$currentDir = -join((Get-Location).Path, "\")
$agent = "cscagent.ps1"
$agentPath = -join($currentDir, $agent)
$credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $securePassword
$password = $credentials.GetNetworkCredential().Password 
$baseURI = "http://localhost:8080/"
$baseAPIURI = -join($baseURI, 'api/')
$authHeader = "Authorization: Bearer $($apiKey)"

#Create Endpoint
#curl -join($baseAPIURI, "endpoints/", $apiKey)
$response = Invoke-WebRequest -Uri (-join($baseAPIURI, "endpoints/")) -UseBasicParsing `
-Headers @{'Authorization' = -join('Bearer ', $apiKey)}
$endpoints = ($response | ConvertFrom-Json).data
$endpoint = $endpoints | where {$_.name -eq $hostname}

Write-Host "Checking if server object exists..."
$endpointId = -1
if (!$endpoint)
{
    Write-Host "Server doesn't exist, creating..."
    $formData = @{
        "name" = $hostname
    }
    $response = Send-API-POST-Request -formData $formData -URI (-join($baseAPIURI, "endpoints/")) -apiKey $apiKey

    if ($response)
    {
        $endpoint = ($response | ConvertFrom-Json).data
        $endpointId = $endpoint.id
    }
}
else
{
    Write-Host "Server already exists."
    $endpointId = $endpoint.id
}

#Save necessary data to files
#$endpointId | Out-File (-join($currentDir, "server_id"))
#$apiKey | Out-File (-join($currentDir, "api_key"))
Write-Host "Endpoint ID: $($endpointId)"

#Create Monitors
Write-Host "Creating monitors..."
$formData = @{
    "name" = -join($hostname, " - CPU");
    "endpoint_id" = $endpointId;
    "run_interval" = "5";
    "run_interval_type" = "minutes";
    "run_interval_grace" = "5";
    "run_interval_grace_type" = "minutes";
    "monitor_breach_value" = "50";
    "monitor_breach_value_type" = "above";
}
$response = Send-API-POST-Request -formData $formData -URI (-join($baseAPIURI, "monitors/")) -apiKey $apiKey
if ($response)
{
    $monitor = ($response | ConvertFrom-Json).data
    $monitorId = $monitor.id
    
    #Get Monitor Code
    $response = Invoke-WebRequest -Uri (-join($baseAPIURI, "monitors/", $monitorId)) -UseBasicParsing `
    -Headers @{'Authorization' = -join('Bearer ', $apiKey)}
    $monitor = ($response | ConvertFrom-Json).data
    $monitorCode = $monitor.code
    
    (New-Object PSObject -Property @{"name"="CPU"; "code"=$monitorCode}) | Export-Csv monitors.data
}

#Create Scheduled Task
Write-Host "Creating Scheduled Task"
#$trigger = New-ScheduledTaskTrigger -SETTING -At TIME -ThrottleLimit 1
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -ThrottleLimit 1
#$action = New-ScheduledTaskAction -Execute "powershell Get-Content $($agentPath) | powershell.exe -nop"
$action = New-ScheduledTaskAction -Execute "powershell" -Argument "-ep Bypass -File `"$($agentPath)`" -baseURI `"$($baseURI)`" -currentDir `"$($currentDir)\`""

Register-ScheduledTask -TaskName "CSC Agent" -Trigger $trigger -Action $action -Description "Agent to gather monitor data and send HTTP requests to Dashboard API" -User $userName -Password $password
