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
    Version: 0.1.0
    Created: 2025.11.06
#>


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
    else {
        Write-Verbose "Folder already exists: $fullPath"
    }
}

# Load config
if (-not (Test-Path $ConfigPath)) {
    Write-Verbose "Config not found! Creating a default one"
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
    "_comment": "Example: git: [{ \"url\": \"ssh://git@agit.kbc.be:7999/~jf69674/ps-logger.git\", \"version\": \"main\" }]",
    "git": []
  }
}
'@
    New-Item -Name $ConfigPath -Path "."
    Set-Content -Path $ConfigPath -Value $jsonConfig
}

$configJson = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$framework = $configJson.framework
$modules = $configJson.modules.required
$dependencies = $configJson.dependencies.git

Write-Verbose "Loaded config for framework: $($framework.name) v$($framework.version)"


# Install required modules
$moduleDependencies = ""
foreach ($mod in $modules) {
    $modName = $mod.name
    $modVersion = $mod.version

    if (-not (Get-Module -ListAvailable -Name $modName)) {
        Write-Verbose "Installing module: $modName ($modVersion)"
        try {
            Install-Module -Name $modName -RequiredVersion $modVersion -Force -Scope CurrentUser
        }
        catch {
            Write-Warning "Failed to install module: $modName"
            exit 1
        }
    }
    else {
        Write-Verbose "Module already installed: $modName"
    }
    $moduleDependencies = "$($moduleDependencies)Import-Module -Name '$modName'`n"
}

# Clone Git dependencies
$gitDependencies = ""
foreach ($dep in $dependencies) {
    $depUrl = $dep.url
    $depVersion = if ($dep.version) { $dep.version } else { "main" }
    $depName = Join-Path "./Modules" (($dep.url -split '/')[-1] -replace '\.git$', '')
    
    if (-not (Test-Path $depName)) {
        Write-Verbose "Cloning $depName from $depUrl..."
        git clone --branch $depVersion $depUrl $depName # check if cloned is on the correct branch
    }
    else {
        Write-Verbose "Dependency already cloned: $depName"
        Write-Verbose "Pulling latest changes for $depName..."
        git --git-dir="$depName/.git" --work-tree="$depName" pull origin $depVersion
    }

    $moduleConfigPath = Join-Path ($depName) "module_config.json"
    if (Test-Path $moduleConfigPath) {
        $moduleConfigJson = Get-Content $moduleConfigPath -Raw | ConvertFrom-Json
        $possibleSettings = $moduleConfigJson.module.possible_settings

        $possibleSettings | ForEach-Object {
            if ($dep.PSObject.Properties.Name -contains $_) {
                $prop_name = $_
                $prop_value = $dep.PSObject.Properties.Where({ $_.Name -eq $prop_name }).Value
                $gitDependencies = "$($gitDependencies)`$GLOBAL:$($prop_name.ToUpper()) = '$prop_value'`n"
            }
        }

        $entryScriptName = Join-Path $depName $moduleConfigJson.module.entry_script
        $gitDependencies = "$($gitDependencies). '$entryScriptName'`n"
    }
}

$startScriptName = "Start-Project.ps1"
if (-not (Test-Path $startScriptName)) {
    New-Item -Name $startScriptName -Path "."
}

$startContent = "$moduleDependencies$gitDependencies& '$(Join-Path "./Scripts" $framework.entry_script)'"

Set-Content -Path $startScriptName -Value $startContent