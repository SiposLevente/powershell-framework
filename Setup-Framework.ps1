<#
.SYNOPSIS
    Sets up a standardized PowerShell automation framework structure and configuration.

.DESCRIPTION
    This script performs the following tasks:

    1. Creates a directory structure for organizing scripts, modules, configs, logs, and tests:
        PowerShellFramework/
        ├── Scripts/   # Main automation scripts
        ├── Modules/   # Custom or third-party PowerShell modules
        ├── Configs/   # Configuration files (e.g., JSON, XML)
        ├── Logs/      # Log output from scripts
        └── Tests/     # Unit and integration tests

    2. Loads framework configuration from a JSON file (default: .\project_config.json).
       - If the file does not exist, a default configuration is generated.

    3. Installs required PowerShell modules listed in the configuration file.

    4. Clones Git-based module dependencies into the Modules folder.
       - Supports specifying branch/version.
       - Loads entry scripts and global settings from each module's config.

    5. Generates a Start-Project.ps1 script that:
       - Imports required modules.
       - Loads Git-based module scripts.
       - Executes the framework's main entry script.

.PARAMETER ConfigPath
    Optional path to the configuration JSON file.
    Default: .\project_config.json

.EXAMPLE
    .\Initialize-Framework.ps1
    Initializes the framework using the default configuration file.

    .\Initialize-Framework.ps1 -ConfigPath ".\custom_config.json"
    Initializes the framework using a custom configuration file.

.NOTES
    Author: Levente Szabolcs Sipos
    Version: 0.1.1
    Created: 2025.11.06
    Updated: 2025.11.20
#>

[CmdletBinding()]
param (
    [string]$ConfigPath = ".\project_config.json"
)

# Define folder structure
$folders = @("Scripts", "Modules", "Configs", "Logs", "Tests")

Write-Verbose "Initializing PowerShell Framework..."

# Create subdirectories
foreach ($folder in $folders) {
    $fullPath = Join-Path "." $folder
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath | Out-Null
        Write-Verbose "Created folder: $fullPath"
    }
}

# Load config
if (-not (Test-Path $ConfigPath)) {
    Write-Verbose "Config not found, creating default one"
    $jsonConfig = 
    @'
{
  "framework": {
    "name": "MyPowerShellFramework",
    "version": "1.0.0",
    "author": "",
    "description": "A modular PowerShell framework for automation tasks.",
    "entry_script": "./Scripts/main.ps1"
  },
  "modules": {
    "_comment": "Example: { \"name\": \"Pester\", \"version\": \">=3.4.0\" }",
    "required": []
  },
  "dependencies": {
    "_comment": "Example: git: [{ \"url\": \"\", \"version\": \"main\" }]",
    "git": []
  }
}
'@
    New-Item -Name $ConfigPath -Path "." | Out-Null
    Set-Content -Path $ConfigPath -Value $jsonConfig
}

$configJson = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$framework = $configJson.framework
$modules = $configJson.modules.required
$dependencies = $configJson.dependencies

Write-Verbose "Loaded config for framework $($framework.name) $($framework.version)"

# Install required modules
$moduleDependencies = ""

foreach ($mod in $modules) {
    try {
        if (-not (Get-Module -ListAvailable -Name $mod.name)) {
            Write-Verbose "Installing module $($mod.name) $($mod.version)"
            Install-Module -Name $mod.name -RequiredVersion $mod.version -Force -Scope CurrentUser -ErrorAction Stop
        }
        $moduleDependencies += "Import-Module -Name '$($mod.name)'" + "`n"
    }
    catch {
        Write-Error "Failed to install module $($mod.name): $_"        
    }
}

function Get-NameByUrl {
    param ([string]$url)
    return (($url -split '/')[ -1 ] -replace '\.git$', '')
}

# Clone Git dependencies
$gitDependenciesString = ""
$requiredDependencyNames = @()

foreach ($dep in $dependencies.git) {

    $depVersion = if ($dep.version) { $dep.version } else { "main" }
    $depName = Get-NameByUrl $dep.url
    
    $clonePath = Join-Path "./Modules" $depName
    
    if (-not (Test-Path $clonePath)) {
        Write-Verbose "Cloning $depName"
        $cloneOutput = & git clone --branch $depVersion $dep.url $clonePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to clone repository '$($dep.url)' into '$clonePath'. Git exit code $LASTEXITCODE. Details:`n$($cloneOutput -join "`n")"
            if (Test-Path $clonePath) { Remove-Item -Recurse -Force -Path $clonePath }
            continue
        }
    }
    else {
        Write-Verbose "Updating $depName"
        $pullOutput = & git --git-dir="$clonePath/.git" --work-tree="$clonePath" pull origin $depVersion 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to update repository '$($dep.url)' at '$clonePath'. Git exit code $LASTEXITCODE. Details:`n$($pullOutput -join "`n")"
            continue
        }
    }
    Write-Verbose "Successfully cloned dependency $depName"
    $requiredDependencyNames += $depName

    $moduleConfigPath = Join-Path $clonePath "module_config.json"

    if (Test-Path $moduleConfigPath) {
        $moduleConfigJson = Get-Content $moduleConfigPath -Raw | ConvertFrom-Json
        $possibleSettings = $moduleConfigJson.module.possible_settings

        foreach ($setting in $possibleSettings) {
            if ($dep.PSObject.Properties.Name -contains $setting) {
                $value = $dep.$setting
                $gitDependenciesString += "`$GLOBAL:$($setting.ToUpper()) = '$value'`n"
            }
        }

        $entryScriptName = Join-Path $clonePath $moduleConfigJson.module.entry_script
        $gitDependenciesString += ". '$entryScriptName'" + "`n"
    }
}

# Remove unused module directories
$moduleFoldersOnDisk = Get-ChildItem -Path "./Modules" -Directory | Select-Object -ExpandProperty Name
if ($moduleFoldersOnDisk.Count -ne 0) {
    Write-Verbose "Checking for unused module folders..."
}

foreach ($folder in $moduleFoldersOnDisk) {
    if ($requiredDependencyNames -notcontains $folder) {
        Write-Verbose "Removing unused module folder $folder"
        Remove-Item -Recurse -Force -Path (Join-Path "./Modules" $folder)
    }
}

$startScriptName = "Start-Project.ps1"
Write-Verbose "Generating Start-Project.ps1 script..."

if (-not (Test-Path $startScriptName)) {
    New-Item -Name $startScriptName -Path "." | Out-Null
}

$startContent = "$moduleDependencies$gitDependenciesString& '$(Join-Path "./Scripts" $framework.entry_script)'"

Set-Content -Path $startScriptName -Value $startContent
Write-Verbose "PowerShell Framework setup completed!"
