
Add-Type -AssemblyName System.IO.Compression.FileSystem

function LogMessage {
    param([string]$messsage, [string]$type)
    $messageColor = $null
    switch ($type) { 
        "ERROR" { $messageColor = "Red"}        
        "WARNING" { $messageColor = "Orange"}
        default { $messageColor = "Green"; $type = "INFO"}

    }
    $dateTime = Get-Date -UFormat '#%a %b %d %T BRT %Y'
    Write-Host "$dateTime - $type - $messsage" -ForegroundColor $messageColor
}

function GetBasicAuth {
    param([string]$user, [string]$pwd)
    $pair = "$($user):$($pwd)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $basicAuthValue = "Basic $encodedCreds"
    $basicAuthValue
}

function ServerStatusCode {
    #param( [string]$url)
    $url = "$serverUri/app/rest"
    $ErrorActionPreference = 'silentlyContinue'
    $statusCode = (Invoke-WebRequest -Method Post -Uri $url -ContentType application/xml).StatusCode    
    $ErrorActionPreference = 'Continue'
    $statusCode
}

function WaitForServerStartup {
    while((ServerStatusCode) -ne 200) {         
        LogMessage "Waiting for server startup. Checking again in 30 seconds."
        Start-Sleep -Seconds 30
    }
    LogMessage "Server up and running."
}

function InstallChoco {
    LogMessage "Chocolatey installation"
    $chocoPath = Join-Path $env:SystemDrive '\\ProgramData\\chocolatey'
    if (!(Test-Path -Path $chocoPath)) {
        iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
    }
}

function InstallServer {
    LogMessage "Server installation" 
    $serverBinPath = Join-Path $serverPath '\\Bin'

    LogMessage "Installing server as service via choco package"
    choco install TeamCity -f -y

    LogMessage "Setting up the Data Directory"
    if (!(Test-Path -Path $serverDataDirectory)) { mkdir $serverDataDirectory }

    LogMessage "Restoring the backup file"
    $backupFile = Join-Path $configPath '\\BasicConfig.zip'
    $dbPropsFile = Join-Path $configPath '\\database.properties'
    Push-Location $serverBinPath
    .\maintainDB.cmd restore -A $serverDataDirectory -F $backupFile -T $dbPropsFile
    Push-Location $configPath

    LogMessage "Setting up the startup properties file"
    $startupFile = Join-Path $serverPath '\\conf\\teamcity-startup.properties'
    $currentDateTime = '#Sun Jan 01 01:01:01 BRT 2017'

    # The datetime is required by TeamCity to read the file
    Out-File -FilePath $startupFile -Encoding utf8 -Force -InputObject $currentDateTime

    # The config here will avoid the first screen launch and therefore allow the the server startup automatically
    Out-File -FilePath $startupFile -Encoding utf8 -Force -Append -InputObject "teamcity.data.path=$serverDataDirectory"

    LogMessage "Restarting server to configs take effect"
    Restart-Service -InputObject TeamCity
    WaitForServerStartup
}

function InstallAgent {
    LogMessage "Agent installation"
    LogMessage "Installing agent as service via choco package"
    choco install TeamCityAgent -f -y -allow-empty-checksums -params "serverUrl=$serverUri agentDir=$serverPath\\buildAgent agentName=$env:COMPUTERNAME"
}

function GetProjects {
    #param([string]$sourceCodeUri, [string]$sourceCodeZipFile, [string]$sourceCodeUnzipPath)
    LogMessage "Getting source code"
    $projectsFile = Join-Path $configPath '\\Projects.json'

    LogMessage "Reading $projectsFile"
    $projects = (Get-Content $projectsFile) -join "`n" | ConvertFrom-Json

    foreach($project in $projects) {

        $sourceCodeProject = $project.Project
        $sourceCodeUri = $project.Uri
        $sourceCodeZipFile = Join-Path $tempFolder "$sourceCodeProject.zip"
        $sourceCodeUnzipPath = Join-Path $tempFolder $sourceCodeProject
        $sourceCodeConfigPath = "$sourceCodeUnzipPath\\*\\TCConfig"
        $destinationPath = Join-Path $projectsFolder $sourceCodeProject

        LogMessage "Getting $sourceCodeZipFile from $sourceCodeUri"
        Invoke-WebRequest -Method Get -Uri $sourceCodeUri -ContentType application/xml -OutFile $sourceCodeZipFile

        LogMessage "Extracting $sourceCodeZipFile to $sourceCodeUnzipPath"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($sourceCodeZipFile, $sourceCodeUnzipPath)

        LogMessage "Moving $sourceCodeConfigPath to $destinationPath"
        Copy-Item -Path $sourceCodeConfigPath -Destination $destinationPath -Recurse -Force

        LogMessage "Cleaning temp files"
        Remove-Item -Path $sourceCodeZipFile -Force -Recurse
        Remove-Item -Path $sourceCodeUnzipPath -Force -Recurse
    }
}

function InstallProjects {
    LogMessage "Projects Installation"
    LogMessage "Stopping server"
    Stop-Service -InputObject TeamCity

    LogMessage "Installing projects based on VCS code"
    Copy-Item -Path "$projectsFolder\\*" -Destination "$serverDataDirectory\\config\\projects\\" -Recurse -Force

    LogMessage "Starting server"
    Restart-Service -InputObject TeamCity
    WaitForServerStartup
}

function TriggerBuilds {
    LogMessage "Triggering builds"
    $uri = "$serverUri/app/rest/buildQueue"
    $buildTypesPath = "$projectsFolder\*\buildTypes\*"
    $buildTypeIds = (ls $buildTypesPath).Name.Replace(".xml","")    
    $basicAuth = GetBasicAuth -user $adminUser -pwd $adminPwd
    $headers = @{
        Authorization = $basicAuth
    }
    foreach($buildTypeId in $buildTypeIds) { 
        $body = "<build><buildType id='$buildTypeId'/><comment><text>Startup build trigger</text></comment></build>"
        Invoke-WebRequest -Method Post -Uri $uri -ContentType application/xml -Headers $headers -Body $body
        LogMessage "Triggered $buildTypeId"
    }
}

$adminUser = ""
$adminPwd = ""
$configPath = Join-Path $env:SystemDrive '\\TeamCityServer'
$projectsFolder = Join-Path $configPath '\\Projects'
$serverPath = Join-Path $env:SystemDrive '\\TeamCity'
$serverUri = "http://localhost:8111"
$serverDataDirectory = Join-Path $env:SystemDrive '\\ProgramData\\JetBrains\\TeamCity'
$tempFolder = Join-Path $env:SystemDrive "\\temp"

LogMessage "Installation started"
InstallChoco
InstallServer
InstallAgent
GetProjects
InstallProjects
TriggerBuilds
LogMessage "Installation finished"

#.\TeamCity\buildAgent\bin\uninstall.bat "C:\\TeamCity\\buildAgent"
#choco uninstall TeamCityAgent -f -y
#choco uninstall TeamCity -f -y
#Remove-Item -Path "C:\\ProgramData\\JetBrains" -Force -Recurse
