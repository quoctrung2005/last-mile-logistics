$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force results,evidence | Out-Null
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Chua co Docker Desktop. Cai va khoi dong Docker Desktop truoc.' }
function D {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: $args" }
}
Start-Transcript -Path evidence/run-log.txt -Force
try {
    D --version
    D run --rm hello-world
    D compose config
    D compose up -d
    $ready = $false
    for ($i=0; $i -lt 60; $i++) {
        try {
            $state=Invoke-RestMethod http://localhost:8080/json/
            if (@($state.workers | Where-Object state -eq 'ALIVE').Count -eq 2) { $ready=$true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'Workers chua dang ky. Xem docker logs spark-worker-1/2.' }
    $state | ConvertTo-Json -Depth 15 | Set-Content evidence/master-before.json -Encoding utf8
    $state.workers | Select-Object id,host,state,cores,memory | Export-Csv evidence/workers.csv -NoTypeInformation
    D ps
    D ps -a
    # Scala REPL doc toan bo script tu stdin, roi thoat.
    Get-Content apps/scala_exercises.scala | & docker exec -i spark-master /opt/spark/bin/spark-shell --master spark://spark-master:7077 --conf spark.driver.host=spark-master --conf spark.driver.bindAddress=0.0.0.0 --conf spark.cores.max=2 --conf spark.executor.memory=512m
    if ($LASTEXITCODE -ne 0) { throw 'Scala shell failed' }
    D exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client --conf spark.driver.host=spark-master --conf spark.driver.bindAddress=0.0.0.0 --conf spark.cores.max=2 --conf spark.executor.memory=512m /opt/spark-apps/exercises.py
    D exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client --conf spark.driver.host=spark-master --conf spark.driver.bindAddress=0.0.0.0 --conf spark.cores.max=2 --conf spark.executor.memory=512m /opt/spark-apps/wordcount.py
    D logs spark-master
    D logs spark-worker-1
    D logs spark-worker-2
    D compose stop
    D compose up -d
    Write-Host 'Hoan thanh cac job. Anh chup Master va thu nghiem loi: xem README.'
} finally { Stop-Transcript }
