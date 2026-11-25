param(
    [string]$DevEcoHome = 'D:\Program Files\Huawei\DevEco Studio',
    [ValidateSet('debug', 'release')][string]$BuildMode = 'debug'
)

$ErrorActionPreference = 'Stop'
if ($BuildMode -eq 'release') {
    throw 'Lite watch installation requires the debug BIN packaging path. Use -BuildMode debug; its JS is minified before signing.'
}
$taskNode = Join-Path $DevEcoHome 'tools\node\node.exe'
$taskHvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
if (!(Test-Path -LiteralPath $taskNode) -or !(Test-Path -LiteralPath $taskHvigor)) {
    throw 'DevEco tools not found. Pass -DevEcoHome with your installation directory.'
}
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:HOS_SDK_HOME = $env:DEVECO_SDK_HOME
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:Path = "$DevEcoHome\tools\node;$DevEcoHome\tools\ohpm\bin;$DevEcoHome\tools\hvigor\bin;$env:Path"

Push-Location $PSScriptRoot
try {
    $taskProfilePath = Join-Path $PSScriptRoot 'build-profile.json5'
    if (!(Test-Path -LiteralPath $taskProfilePath)) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-profile.template.json5') -Destination $taskProfilePath
        Write-Output 'Created local unsigned build-profile.json5. Configure signing in DevEco Studio for device installation.'
    }
    & $taskNode (Join-Path $PSScriptRoot 'scripts\validate-signing-config.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Invalid phone companion signing configuration.' }
    & $taskNode $taskHvigor --mode module -p module=entry@default -p product=default -p "buildMode=$BuildMode" assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Hvigor failed with exit code $LASTEXITCODE" }
    $taskProfileText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'build-profile.json5'))
    $taskSigned = [regex]::IsMatch($taskProfileText, '"signingConfig"\s*:\s*"[^"]+"')
    $taskSuffix = if ($taskSigned) { 'signed' } else { 'unsigned' }
    $taskHap = Join-Path $PSScriptRoot "entry\build\default\outputs\default\entry-default-$taskSuffix.hap"
    if (!(Test-Path -LiteralPath $taskHap)) { throw "$taskSuffix HAP was not generated." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $taskArchive = [IO.Compression.ZipFile]::OpenRead($taskHap)
    try {
        $taskExpectedBin = "entry-default-$taskSuffix.bin"
        if ($taskArchive.Entries.Count -ne 1 -or $taskArchive.Entries[0].FullName -ne $taskExpectedBin) {
            throw 'Invalid Lite installation HAP: expected a single application BIN.'
        }
    } finally {
        $taskArchive.Dispose()
    }
    Write-Output "$taskSuffix $BuildMode HAP: $taskHap"
} finally {
    Pop-Location
}
