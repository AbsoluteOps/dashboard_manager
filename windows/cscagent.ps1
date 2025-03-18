param(
  [Parameter(Mandatory=$true)]
  [String]$baseURI,
  
  [Parameter(Mandatory=$true)]
  [String]$currentDir
)

function Send-API-POST-Request
{
    param(
        $formData,
        $URI,
        $apiKey
    )
    
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $formDataKeys = ""
    $formDataValues = ""
    
    $bodyLines = ""
    foreach ($h in $formData.Keys)
    {
        $bodyLines += "--$boundary$($LF)"
        $bodyLines += "Content-Disposition: form-data; name=`"$($h)`"$($LF)$($LF)"
        $bodyLines += "$($formData.$h)$($LF)"
    }
    $bodyLines += "--$boundary--$LF" 
    
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

$monitors = Import-Csv "$($currentDir)monitors.data"

$cpu_total = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue.ToString("#.##")

echo $baseURI
echo $monitors.code
echo $cpu_total
#Send value to CPU Monitor
$response = Invoke-WebRequest -Uri (-join($baseURI, "webhook-monitor/", $monitors.code, "/?value=", $cpu_total)) -UseBasicParsing