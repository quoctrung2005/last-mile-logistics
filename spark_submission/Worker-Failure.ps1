$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
function Snapshot($name) {
  $s=Invoke-RestMethod http://localhost:8080/json/
  $s | ConvertTo-Json -Depth 15 | Set-Content "evidence/$name.json" -Encoding utf8
  $s.workers | Format-Table id,host,state,cores,memory
}
Snapshot 'failure-before'
docker stop spark-worker-1
if ($LASTEXITCODE -ne 0) { throw 'Stop failed' }
try {
  Write-Host 'Cho Master phat hien Worker mat ket noi (co the hon 60 giay).'
  Start-Sleep -Seconds 65
  Snapshot 'failure-during'
} finally { docker start spark-worker-1 }
Start-Sleep -Seconds 10
Snapshot 'failure-after'
