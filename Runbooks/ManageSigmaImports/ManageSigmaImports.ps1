[CmdletBinding()]
param (
    # The name of the resource group containing your Sentinel workspace
    [Parameter()]
    [string]
    $ResourceGroupName = 'Sentinel',

    # The name of the Log Analytics workspace containing your Sentinel workspace
    [Parameter()]
    [string]
    $WorkspaceName = 'SentinelWorkspace'
)
# Install the latest version of Git for Windows
Write-Output "Installing Git for Windows"
# Do some hacky parsing of the releases page to get the latest download link
try {
    $response = Invoke-WebRequest -Uri 'https://git-scm.com/downloads/win'
}
catch {
    Throw "Failed to determine latest release URI of Git for Windows: $_"
}
$downloadUri = ([regex]::Match($response.RawContent, 'id="auto-download-link" href="([^"]+)"')).Groups[1].Value
if ($downloadUri -match '^https://github.com/git-for-windows/git/releases/download/.+-64-bit\.exe$') {
    Write-Output "Downloading Git for Windows from $downloadUri"
    try {
        Invoke-WebRequest -Uri $downloadUri -OutFile "$env:Temp\gitInstaller.exe"
        Start-Process -FilePath "$env:Temp\gitInstaller.exe" -ArgumentList '/VERYSILENT /NORESTART' -Wait
        # Refresh the path
        $tempPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $tempPath += ";$([System.Environment]::GetEnvironmentVariable('Path', 'User'))"
        $env:Path = $tempPath
    }
    catch {
        Throw "Failed to download or install Git for Windows: $_"
    }
} else {
    Throw "Failed to determine latest release URI of Git for Windows"
}

# Install the latest version of python
# Do some hacky parsing of the releases page to get the latest version
try {
    $response = Invoke-WebRequest -Uri 'https://www.python.org/downloads/windows/'
}
catch {
    Write-Error 
    Throw $_
}

$version = ([regex]::Match($response.RawContent, 'Latest Python 3 Release - Python (3\.\d+\.\d+)')).Groups[1].Value
if (([version]$version).GetType().Name -ne 'Version') {
    Write-Error "Failed to determine latest release"
    exit 1
}

# For some stupid reason, the automation runbook is blopcking the installation of python
# The following steps were taken from https://plainenglish.io/blog/install-python-on-a-locked-down-pc-without-local-admin-37a440c42c12
$downloadUri = "https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip"
Write-Output "Installing Python version $version"
try {
    Invoke-WebRequest -Uri $downloadUri -OutFile "$env:Temp\python-$version-embed-amd64.zip"
    Expand-Archive -Path "$env:Temp\python-$version-embed-amd64.zip" -DestinationPath "$env:LocalAppData\Programs\Python"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$env:Temp\get-pip.py"
    Start-Process -FilePath "$env:LocalAppData\Programs\Python\python.exe" -ArgumentList "$env:Temp\get-pip.py" -Wait `
        -NoNewWindow
    $env:Path += ";$env:LocalAppData\Programs\Python"
    $env:Path += ";$env:LocalAppData\Programs\Python\Scripts"
    $config = Get-Item "$env:LocalAppData\Programs\Python\*._pth" | Select-Object -First 1
    ($config | Get-Content -raw) -replace "#import site","import site" | Set-Content $config.FullName
}
catch {
    Throw "Failed to download or install Python: $_"
}

# Install the Sigma CLI
Write-Output "Installing Sigma CLI"
try {
    Start-Process -FilePath 'python.exe' -ArgumentList '-m pip install sigma-cli' -Wait
}
catch {
    Throw "Failed to install Sigma CLI: $_"
}

# Install the Sigma Kusto backend
Write-Output "Installing Sigma Kusto backend"
try {
    Start-Process -FilePath 'sigma.exe' -ArgumentList 'plugin install kusto' -Wait
}
catch {
    Throw "Failed to install the Kusto Sigma-cli backed: $_"
}

# Clone the sigma repo
Write-Output "Cloning the Sigma repository"
try {
    git clone https://github.com/SigmaHQ/sigma.git "$env:Temp\sigma"
}
catch {
    Write-Error "Failed to clone the Sigma repository: $_"
}

Connect-AzAccount -Identity
dir "$env:Tmp\sigma\*.xml" | Select FullName
Get-Item "$env:Temp\sigma\rules\windows\file\file_access\*.yml" | ForEach-Object {
    Set-AzSentinelContentTemplateFromSigmaRule -File $_ -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroupName
}