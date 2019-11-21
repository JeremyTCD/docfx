param(
    [string] $configuration = "Release",
    [switch] $raw = $true,
    [switch] $prod = $true,
    [switch] $skipTests = $true,
    [switch] $release = $false
)
################################################################################################
# Usage:
# Run build.ps1
#   [-configuration Configuration]: Default to be Release
#   [-raw]: If it's set, the build process will skip updating template
#   [-prod]: If it's set, the build process will update version
#   [-skipTests]: If it's set, running unit tests will be skipped
################################################################################################

$ErrorActionPreference = 'Stop'
$releaseBranch = "master"
$dotnetCommand = "dotnet"
$gitCommand = "git"
$framework = "net462"
$packageVersion = "2.39.8"
$assemblyVersion = "1.0.0.0"

if ([environment]::OSVersion.Platform -eq "Win32NT") {
    $os = "Windows"
}
else {
    $os = "Linux"
}
Write-Host "Running on OS $os"

if ($os -eq "Windows") {
    $nugetCommand = "$env:LOCALAPPDATA/Nuget/Nuget.exe"
}
else {
    $nugetCommand = "nuget"
}

$scriptPath = $MyInvocation.MyCommand.Path
$scriptHome = Split-Path $scriptPath
$versionCsFolderPath = $scriptHome + "/TEMP/"
$versionCsFilePath = $versionCsFolderPath + "version.cs"
$versionFsFilePath = $versionCsFolderPath + "version.fs"

$global:LASTEXITCODE = $null

Push-Location $scriptHome

function NugetPack {
    param($basepath, $nuspec, $version)
    if (Test-Path $nuspec) {
        & $nugetCommand pack $nuspec -Version $version -OutputDirectory artifacts/$configuration -BasePath $basepath
        ProcessLastExitCode $lastexitcode "$nugetCommand pack $nuspec -Version $version -OutputDirectory artifacts/$configuration -BasePath $basepath"
    }
}

function ProcessLastExitCode {
    param($exitCode, $msg)
    if ($exitCode -eq 0) {
        Write-Host "Success: $msg
        " -ForegroundColor Green
    }
    else {
        Write-Host "Error $($exitCode): $msg
        " -ForegroundColor Red
        Pop-Location
        Exit 1
    }
}

function ValidateCommand {
    param($command)
    return (Get-Command $command -ErrorAction SilentlyContinue) -ne $null
}

# Check if dotnet cli exists globally
if (-not(ValidateCommand("dotnet"))) {
    ProcessLastExitCode 1 "Dotnet CLI is not successfully configured. Please follow https://www.microsoft.com/net/core to install .NET Core."
}

# Check if nuget.exe exists
if (-not(ValidateCommand($nugetCommand))) {
    Write-Host "Downloading NuGet.exe..."
    mkdir -Path "$env:LOCALAPPDATA/Nuget" -Force
    $ProgressPreference = 'SilentlyContinue'
    [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultCredentials
    Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nugetCommand
}

# Update template
if ($raw -eq $false) {
    ./UpdateTemplate.ps1
    ProcessLastExitCode $lastexitcode "Update template"
}
else {
    Write-Host "Skip updating template"
}

Write-Host "Using package version $packageVersion, and assembly version $assemblyVersion, assembly file version $assemblyFileVersion"

foreach ($sln in (Get-ChildItem *.sln)) {
    Write-Host "Start building $($sln.FullName)"

    & dotnet restore $sln.FullName /p:Version=$packageVersion
    ProcessLastExitCode $lastexitcode "dotnet restore $($sln.FullName) /p:Version=$packageVersion"

    if ($os -eq "Windows") {
        & dotnet build $sln.FullName -c $configuration -v n /m:1
        ProcessLastExitCode $lastexitcode "dotnet build $($sln.FullName) -c $configuration -v n /m:1"
    }
    else {
        & msbuild $sln.FullName /p:Configuration=$configuration /verbosity:n /m:1
        ProcessLastExitCode $lastexitcode "msbuild $($sln.FullName) /p:Configuration=$configuration /verbosity:n /m:1"        
    }
}

# dotnet pack first
foreach ($proj in (Get-ChildItem -Path "src" -Include *.[cf]sproj -Exclude 'docfx.msbuild.csproj' -Recurse)) {
    if ($os -eq "Windows") {
        & dotnet pack $proj.FullName -c $configuration -o $scriptHome/artifacts/$configuration --no-build /p:Version=$packageVersion
        ProcessLastExitCode $lastexitcode "dotnet pack $($proj.FullName) -c $configuration -o $scriptHome/artifacts/$configuration --no-build /p:Version=$packageVersion"
    }
 else {
        & nuget pack $($proj.FullName) -Properties Configuration=$configuration -OutputDirectory $scriptHome/artifacts/$configuration -Version $packageVersion
        ProcessLastExitCode $lastexitcode "nuget pack $($proj.FullName) -Properties Configuration=$configuration -OutputDirectory $scriptHome/artifacts/$configuration -Version $packageVersion"
    }
}

# Pack docfx.console
$docfxTarget = "target/$configuration/docfx";
if (-not(Test-Path -path $docfxTarget)) {
    New-Item $docfxTarget -Type Directory
}

Copy-Item -Path "src/nuspec/docfx.console/build" -Destination $docfxTarget -Force -Recurse
Copy-Item -Path "src/nuspec/docfx.console/content" -Destination $docfxTarget -Force -Recurse

$packages = @{
    "docfx" = @{
        "proj"    = $null;
        "nuspecs" = @("src/nuspec/docfx.console/docfx.console.nuspec");
    };
}

# Pack plugins and tools
foreach ($proj in (Get-ChildItem -Path ("src") -Include *.csproj -Recurse)) {
    $name = $proj.BaseName
    if ($packages.ContainsKey($name)) {
        $packages[$name].proj = $proj
    }
    $nuspecs = Join-Path $proj.DirectoryName "*.nuspec" -Resolve
    if ($nuspecs -ne $null) {
        if ($packages.ContainsKey($name)) {
            $packages[$name].nuspecs = $packages[$name].nuspecs + $nuspecs
        }
        else {
            $packages[$name] = @{
                nuspecs = $nuspecs;
                proj    = $proj;
            }
        }
    }
}

foreach ($name in $packages.Keys) {
    $val = $packages[$name]
    $proj = $val.proj

    if ($proj -eq $null) {
        Write-Host $package
        ProcessLastExitCode 1 "$name does not have project found"
    }

    $outputFolder = "$scriptHome/target/$configuration/$name"
    # publish to target folder before pack
    & dotnet publish $proj.FullName -c $configuration -f $framework -o $outputFolder
    ProcessLastExitCode $lastexitcode "dotnet publish $($proj.FullName) -c $configuration -f $framework -o $outputFolder"

    $nuspecs = $val.nuspecs
    foreach ($nuspec in $nuspecs) {
        NugetPack $outputFolder $nuspec $packageVersion
    }
}

Write-Host "Build succeeds." -ForegroundColor Green
Pop-Location

