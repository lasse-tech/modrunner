#Requires -Version 5.1
<#
.SYNOPSIS
    Build, test and install modrunner on Windows.

.DESCRIPTION
    The Makefile is the equivalent on macOS, but most of what it does -- the app
    bundle, the disk image, notarisation, Launch Services -- has no meaning here,
    and the targets that do are single `swift` calls. This covers those, plus
    the two things that genuinely differ: what "install" means on Windows, and
    getting the icon into the executable, which SwiftPM will not do.

    There is no app to install. Package.swift leaves the SwiftUI target out off
    Apple's platforms, so the whole program is modrunner.exe and the windowed
    interface is `modrunner window [module]...`.

.EXAMPLE
    .\build.ps1 install
    .\build.ps1 test
    .\build.ps1 run -Module "Examples\Take it slow.med"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'build', 'test', 'run', 'icons', 'install', 'uninstall',
                 'associate', 'associations', 'lint', 'clean', 'distclean')]
    [string] $Task = 'help',

    [ValidateSet('debug', 'release')]
    [string] $Config = 'release',

    [string] $Module = 'Examples\Happy Hour.med',

    # Per-user by default, which is why none of this needs an administrator.
    [string] $Prefix = "$env:LOCALAPPDATA\Programs\ModRunner"
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$AppName  = 'ModRunner'
$ExeName  = 'modrunner.exe'
$Bundle   = 'ModRunner_ModRunnerKit.resources'
$Shortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
$IconDir  = 'brand\windows'
$AppIcon  = 'ModRunner.ico'

# One ProgId per extension rather than one for both, so each can carry its own
# document icon -- the same split the macOS side makes with two .icns files.
$FileTypes = [ordered]@{
    '.med' = @{ ProgId = 'ModRunner.MED'; Icon = 'ModRunnerDocMED.ico'; Label = 'MED / OctaMED module' }
    '.mod' = @{ ProgId = 'ModRunner.MOD'; Icon = 'ModRunnerDocMOD.ico'; Label = 'ProTracker module' }
}

function Write-Step([string] $Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Swift([string[]] $SwiftArguments) {
    & swift @SwiftArguments
    if ($LASTEXITCODE -ne 0) {
        throw "swift $($SwiftArguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# `.build\release` is a symbolic link into the triple's directory, and SwiftPM
# cannot create it here without Developer Mode -- it warns and carries on. So ask
# for the path rather than assuming it.
function Get-BinPath {
    $output = & swift build -c $Config --show-bin-path
    if ($LASTEXITCODE -ne 0) { throw 'could not determine the build directory' }
    $lines = @($output | Where-Object { $_ -match '\S' })
    return $lines[-1].Trim()
}

# The .ico files are repacked from the macOS artwork and committed, so a build
# does not need this. It is here for when the artwork changes.
function Invoke-IconsTask {
    Write-Step 'Repacking the brand artwork into .ico files'
    $tool = Join-Path ([System.IO.Path]::GetTempPath()) 'modrunner-mkicons.exe'
    # `swift Scripts\...swift` cannot run it: the interpreter fails to resolve
    # Foundation on Windows, so it is compiled and then run.
    & swiftc -O 'Scripts\make-windows-icons.swift' -o $tool
    if ($LASTEXITCODE -ne 0) { throw 'could not build the icon tool' }
    & $tool
    if ($LASTEXITCODE -ne 0) { throw 'the icon tool failed' }
}

# Windows takes a program's icon from its resource section, and SwiftPM puts
# nothing there. llvm-rc ships with the Swift toolchain, so this needs no
# Visual Studio; without it the build still works and the icon is just absent.
function Get-ResourceObject {
    $rc  = Join-Path $IconDir "$AppName.rc"
    $res = Join-Path $IconDir "$AppName.res"
    $ico = Join-Path $IconDir $AppIcon
    if (-not (Test-Path -LiteralPath $rc) -or -not (Test-Path -LiteralPath $ico)) {
        Write-Host "No icon to compile in ($IconDir); run .\build.ps1 icons to make one."
        return $null
    }
    if ($null -eq (Get-Command llvm-rc -ErrorAction SilentlyContinue)) {
        Write-Host 'llvm-rc is not on PATH; building without an icon.'
        return $null
    }
    $current = Get-Location
    try {
        Set-Location -LiteralPath $IconDir
        & llvm-rc /FO "$AppName.res" "$AppName.rc"
        if ($LASTEXITCODE -ne 0) { throw 'llvm-rc failed' }
    } finally {
        Set-Location -LiteralPath $current
    }
    return (Resolve-Path -LiteralPath $res).Path
}

function Invoke-BuildTask {
    Write-Step "Building the $Config build of modrunner"
    $arguments = @('build', '-c', $Config, '--product', 'modrunner')
    $res = Get-ResourceObject
    if ($null -ne $res) { $arguments += @('-Xlinker', $res) }
    Invoke-Swift $arguments
    Write-Host "Built $(Join-Path (Get-BinPath) $ExeName)"
}

function Invoke-TestTask {
    Write-Step 'Running the test suite'
    Invoke-Swift @('test')
}

function Invoke-RunTask {
    Write-Step "Opening $Module in a window"
    Invoke-Swift @('run', '-c', $Config, 'modrunner', 'window', $Module)
}

function Invoke-LintTask {
    if ($null -eq (Get-Command swiftlint -ErrorAction SilentlyContinue)) {
        Write-Host 'SwiftLint is not installed; skipping.'
        return
    }
    Write-Step 'Linting'
    & swiftlint lint --quiet
}

function Invoke-CleanTask {
    Write-Step 'Removing build products'
    Invoke-Swift @('package', 'clean')
    foreach ($path in @('build', (Join-Path $IconDir "$AppName.res"))) {
        if (Test-Path -LiteralPath $path) { Remove-Item -Recurse -Force -LiteralPath $path }
    }
}

function Invoke-DistcleanTask {
    Invoke-CleanTask
    foreach ($directory in @('.build', '.swiftpm')) {
        if (Test-Path -LiteralPath $directory) {
            Remove-Item -Recurse -Force -LiteralPath $directory
        }
    }
}

function Add-ToUserPath([string] $Directory) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $current) { $current = '' }
    $entries = @($current -split ';' | Where-Object { $_ -ne '' })
    if ($entries -contains $Directory) { return $false }
    [Environment]::SetEnvironmentVariable('Path', (($entries + $Directory) -join ';'), 'User')
    return $true
}

function Remove-FromUserPath([string] $Directory) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $current) { return $false }
    $entries = @($current -split ';' | Where-Object { $_ -ne '' })
    if ($entries -notcontains $Directory) { return $false }
    $kept = @($entries | Where-Object { $_ -ne $Directory })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    return $true
}

# The shell caches file associations and their icons. Without this the change
# only turns up after a sign-out.
function Update-ShellAssociations {
    if (-not ('ModRunner.Shell32' -as [type])) {
        $signature = '[System.Runtime.InteropServices.DllImport("shell32.dll")]' +
                     ' public static extern void SHChangeNotify(int eventId, uint flags,' +
                     ' System.IntPtr item1, System.IntPtr item2);'
        Add-Type -Namespace 'ModRunner' -Name 'Shell32' -MemberDefinition $signature
    }
    # SHCNE_ASSOCCHANGED, SHCNF_IDLIST
    [ModRunner.Shell32]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Invoke-InstallTask {
    Invoke-BuildTask
    $bin = Get-BinPath

    Write-Step "Installing into $Prefix"
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Copy-Item -LiteralPath (Join-Path $bin $ExeName) -Destination $Prefix -Force

    # This is not optional. SwiftPM's generated `Bundle.module` looks next to the
    # executable first and then at an absolute build path compiled into the
    # binary; with neither present it calls fatalError, and every localised
    # string -- which includes every load error -- takes the program down with it.
    $resources = Join-Path $bin $Bundle
    if (-not (Test-Path -LiteralPath $resources)) {
        throw "the resource bundle is missing from $bin; the install would crash on the first localised string"
    }
    $installedBundle = Join-Path $Prefix $Bundle
    if (Test-Path -LiteralPath $installedBundle) {
        Remove-Item -Recurse -Force -LiteralPath $installedBundle
    }
    Copy-Item -LiteralPath $resources -Destination $Prefix -Recurse -Force

    # The document icons cannot be read out of the executable -- it carries only
    # its own -- so the .ico files come along and the registry points at them.
    if (Test-Path -LiteralPath $IconDir) {
        Copy-Item -Path (Join-Path $IconDir '*.ico') -Destination $Prefix -Force
    }

    # The examples come along so the Start menu entry has something to play.
    $examples = Join-Path $Prefix 'Examples'
    if (Test-Path -LiteralPath 'Examples') {
        New-Item -ItemType Directory -Force -Path $examples | Out-Null
        Copy-Item -Path 'Examples\*' -Destination $examples -Force
    }

    if (Add-ToUserPath $Prefix) {
        Write-Host "Added $Prefix to your PATH. Open a new terminal for it to take effect."
    } else {
        Write-Host "$Prefix is already on your PATH."
    }

    $exe = Join-Path $Prefix $ExeName
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Shortcut)
    $link.TargetPath = $exe
    # The window opens empty and Project > Open Files fills it, so the entry
    # needs no arguments -- but the examples are there, so it starts with them.
    if (Test-Path -LiteralPath $examples) {
        $playlist = @(Get-ChildItem -LiteralPath $examples -File |
                      Where-Object { $_.Extension -in @('.med', '.mod') } |
                      ForEach-Object { '"' + $_.FullName + '"' })
        $link.Arguments = (@('window') + $playlist) -join ' '
    } else {
        $link.Arguments = 'window'
    }
    $link.WorkingDirectory = $Prefix
    $link.Description = 'MED / OctaMED and ProTracker module player'
    $link.IconLocation = "$exe,0"
    $link.Save()
    Write-Host 'Added a Start menu entry.'

    Write-Host ''
    Write-Host "Installed. Try:  modrunner window"
    Write-Host 'Associate .med and .mod with it:  .\build.ps1 associate'
}

function Invoke-AssociateTask {
    $exe = Join-Path $Prefix $ExeName
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "modrunner is not installed in $Prefix; run .\build.ps1 install first"
    }

    Write-Step 'Registering .med and .mod'
    $classes = 'HKCU:\Software\Classes'
    foreach ($extension in $FileTypes.Keys) {
        $type = $FileTypes[$extension]
        $progId = $type.ProgId
        $icon = Join-Path $Prefix $type.Icon
        # Falls back to the executable's own icon if the document one is not
        # installed, which is better than a registry entry pointing at nothing.
        if (-not (Test-Path -LiteralPath $icon)) { $icon = "$exe,0" }

        New-Item -Path "$classes\$progId\shell\open\command" -Force | Out-Null
        New-Item -Path "$classes\$progId\DefaultIcon" -Force | Out-Null
        Set-ItemProperty -Path "$classes\$progId" -Name '(default)' -Value $type.Label
        Set-ItemProperty -Path "$classes\$progId\DefaultIcon" -Name '(default)' -Value $icon
        Set-ItemProperty -Path "$classes\$progId\shell\open\command" -Name '(default)' -Value ('"' + $exe + '" window "%1"')

        New-Item -Path "$classes\$extension" -Force | Out-Null
        Set-ItemProperty -Path "$classes\$extension" -Name '(default)' -Value $progId
    }

    Update-ShellAssociations
    Write-Host 'Done. Windows may still ask once which app to use, and remember the answer.'
}

function Invoke-AssociationsTask {
    $classes = 'HKCU:\Software\Classes'
    foreach ($extension in $FileTypes.Keys) {
        $key = "$classes\$extension"
        if (Test-Path -LiteralPath $key) {
            $value = (Get-ItemProperty -LiteralPath $key).'(default)'
            Write-Host ('{0,-6} {1}' -f $extension, $value)
            $icon = "$classes\$value\DefaultIcon"
            if (Test-Path -LiteralPath $icon) {
                Write-Host ('{0,-6}   icon: {1}' -f '', (Get-ItemProperty -LiteralPath $icon).'(default)')
            }
        } else {
            Write-Host ('{0,-6} not registered for this user' -f $extension)
        }
    }
}

function Invoke-UninstallTask {
    Write-Step "Removing $Prefix"
    if (Test-Path -LiteralPath $Prefix) { Remove-Item -Recurse -Force -LiteralPath $Prefix }
    if (Test-Path -LiteralPath $Shortcut) { Remove-Item -Force -LiteralPath $Shortcut }
    if (Remove-FromUserPath $Prefix) { Write-Host "Removed $Prefix from your PATH." }

    $classes = 'HKCU:\Software\Classes'
    foreach ($extension in $FileTypes.Keys) {
        $progId = $FileTypes[$extension].ProgId
        if (Test-Path -LiteralPath "$classes\$progId") {
            Remove-Item -Recurse -Force -LiteralPath "$classes\$progId"
        }
        # Only give back an extension this script claimed; something else may
        # own it by now.
        $key = "$classes\$extension"
        if (Test-Path -LiteralPath $key) {
            if ((Get-ItemProperty -LiteralPath $key).'(default)' -eq $progId) {
                Remove-Item -Recurse -Force -LiteralPath $key
            }
        }
    }
    Update-ShellAssociations
    Write-Host 'Uninstalled.'
}

function Invoke-HelpTask {
    Write-Host "$AppName -- available tasks:"
    Write-Host ''
    Write-Host '  build          Compile modrunner, with its icon'
    Write-Host '  test           Run the test suite'
    Write-Host '  run            Open a module in a window'
    Write-Host '  icons          Repack the brand artwork into .ico files'
    Write-Host '  install        Copy modrunner into Programs, add it to PATH'
    Write-Host '  uninstall      Undo install, including the associations'
    Write-Host '  associate      Make modrunner open .med and .mod files'
    Write-Host '  associations   Show what opens .med and .mod today'
    Write-Host '  lint           Run SwiftLint, if it is installed'
    Write-Host '  clean          Remove build products'
    Write-Host '  distclean      Also remove .build and .swiftpm'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host "  -Config $Config"
    Write-Host "  -Module `"$Module`""
    Write-Host "  -Prefix $Prefix"
    Write-Host ''
    Write-Host 'There is no app bundle on Windows: Package.swift leaves the SwiftUI'
    Write-Host 'target out off Apple platforms, so modrunner.exe is the whole program'
    Write-Host 'and `modrunner window` is its interface. It opens without a module.'
}

switch ($Task) {
    'help'         { Invoke-HelpTask }
    'build'        { Invoke-BuildTask }
    'test'         { Invoke-TestTask }
    'run'          { Invoke-RunTask }
    'icons'        { Invoke-IconsTask }
    'install'      { Invoke-InstallTask }
    'uninstall'    { Invoke-UninstallTask }
    'associate'    { Invoke-AssociateTask }
    'associations' { Invoke-AssociationsTask }
    'lint'         { Invoke-LintTask }
    'clean'        { Invoke-CleanTask }
    'distclean'    { Invoke-DistcleanTask }
}
