param(
    [string]$DevEcoHome = 'D:\Program Files\Huawei\DevEco Studio',
    [ValidateSet('debug', 'release')][string]$BuildMode = 'debug'
)

$ErrorActionPreference = 'Stop'
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
    & $taskNode $taskHvigor --mode module -p module=entry@default -p product=default -p "buildMode=$BuildMode" assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Hvigor failed with exit code $LASTEXITCODE" }
    $taskProfileText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'build-profile.json5'))
    $taskSigned = [regex]::IsMatch($taskProfileText, '"signingConfig"\s*:\s*"[^"]+"')
    $taskSuffix = if ($taskSigned) { 'signed' } else { 'unsigned' }
    $taskHap = Join-Path $PSScriptRoot "entry\build\default\outputs\default\entry-default-$taskSuffix.hap"
    if (!(Test-Path -LiteralPath $taskHap)) { throw "$taskSuffix HAP was not generated." }
    Write-Output "$taskSuffix $BuildMode HAP: $taskHap"
} finally {
    Pop-Location
}
