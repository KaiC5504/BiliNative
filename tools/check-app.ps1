# PowerShell entry point for tools/check-app.sh (same options); the check itself runs in WSL.
$here = $PSScriptRoot -replace '\\', '/'
$wslPath = '/mnt/' + $here.Substring(0, 1).ToLower() + $here.Substring(2) + '/check-app.sh'
wsl.exe -d Ubuntu --exec bash $wslPath @args
exit $LASTEXITCODE
