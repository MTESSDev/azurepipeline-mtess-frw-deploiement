$sourceDir = Get-VstsInput -name "sourceDir"
$apiSiteWeb = Get-VstsInput -name "apiSiteWeb"
$noPublicSystemeAutorise = Get-VstsInput -name "noPublicSystemeAutorise"
$apiKey = Get-VstsInput -name "apiKey"

Write-Host "==================================="
Write-Host "= Utilitaire de deploiement FRW   ="
Write-Host "= Copyright MTESS 2022            ="
Write-Host "==================================="
Write-Host "Repertoire source: $sourceDir"

if(-not (Test-Path $sourceDir))
{
    throw("Le repertoire source '$sourceDir' est introuvable. Arret du traitement...")
}

$tempPath = $env:AGENT_TEMPDIRECTORY
if (-not $tempPath){
    $tempPath = "C:\Windows\Temp"
}

$guid = [guid]::NewGuid()
$tempZipFilename = "$tempPath\$guid.zip"
Write-Output "Fichier Zip: $tempZipFilename"
Write-Output "Compression des fichiers..."
Add-Type -Assembly System.IO.Compression.FileSystem
$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
[System.IO.Compression.ZipFile]::CreateFromDirectory($sourceDir, $tempZipFilename, $compressionLevel, $false)
Write-Output "Compression terminee."

Write-Output "Deploiement des formulaires vers FRW..."
Write-Output "Convertir Base64"
$zip = [convert]::ToBase64String((Get-Content -path $tempZipFilename -Encoding byte -Raw))
Write-Output "Base64 fait... $($zip.Length) bytes"

if(-not $apiSiteWeb)
{
    $apiSiteWeb = "QA"
}

$Uri = ""
switch (($apiSiteWeb).ToUpper()) {
    DEBUG { $Uri = "https://localhost:44341/api/v1/SIS/DeployerSysteme" }
    QA    { $Uri = "https://formulaires.it.mtess.gouv.qc.ca/api/v1/SIS/DeployerSysteme" }
    PROD  { $Uri = "https://formulaires.mtess.gouv.qc.ca/api/v1/SIS/DeployerSysteme" }
    Default { $Uri = $apiSiteWeb }
}

$headers = @{
    "X-ApiKey" = $apiKey
    "X-NoPublicSystemeAutorise" = $noPublicSystemeAutorise
}
$contentType = "application/json"

Write-Output "Convertir en json..."
$body = @{
    zip = $zip
} | ConvertTo-Json

Write-Output "Transmettre au service web..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $result = Invoke-RestMethod -Method Post -Uri $Uri -ContentType $contentType -Headers $headers -Body $body
}
catch
{
    Write-Host "Echec du transfert."
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription

    $responseBody = $null
    $responseStream = if ($_.Exception.Response) { $_.Exception.Response.GetResponseStream() } else { $null }
    if ($responseStream) {
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
    }

    if ($responseBody) {
        Write-Error "Reponse serveur: $responseBody"
    } else {
        Write-Error "Erreur: $($_.Exception.Message)"
    }

    Write-VstsSetResult -Result "Failed" -Message "Echec du deploiement"
    exit 1
}
finally
{
    Remove-Item $tempZipFilename -ErrorAction SilentlyContinue
}

Write-Output "Termine."
Write-VstsSetResult -Result "Succeeded" -message "DONE"
