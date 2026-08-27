param(
    [string]$Template = "node-red/flows.json",
    [string]$Deployed = "$env:USERPROFILE\.node-red\flows.json",
    [switch]$RemoveTestNodes
)

<#
Sincroniza el flujo desplegado de Node-RED desde el template del proyecto.

- Copia el `tree` (address space) del nodo opc-ua-server del template al desplegado.
- Regenera el array de tags de `oip-sim-func` a partir de las variables del tree
  (name + nodeId), para que lectura y servidor nunca se desfasen.
- Conserva los nodos propios del usuario (plca1, OPCLOCAL, opc1, etc.).
- Opcionalmente borra nodos de prueba conocidos (-RemoveTestNodes).
- Hace backup del desplegado en <deployed>.bak-opencode antes de escribir.
#>

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $Template)) { throw "Template no encontrado: $Template" }
if (-not (Test-Path -LiteralPath $Deployed)) { throw "Desplegado no encontrado: $Deployed" }

$tmp = Get-Content -Raw -LiteralPath $Template  | ConvertFrom-Json
$dep = Get-Content -Raw -LiteralPath $Deployed  | ConvertFrom-Json

$tmpServer = $tmp | Where-Object { $_.type -eq "opc-ua-server" -and $_.tree } | Select-Object -First 1
$depServer = $dep | Where-Object { $_.type -eq "opc-ua-server" -and $_.tree } | Select-Object -First 1
if (-not $tmpServer -or -not $depServer) { throw "Nodo opc-ua-server con tree no encontrado en template y/o desplegado" }

$tmpFunc = $tmp | Where-Object { $_.id -eq "oip-sim-func" } | Select-Object -First 1
if (-not $tmpFunc) { throw "Nodo oip-sim-func no encontrado en el template" }

$backup = "$Deployed.bak-opencode"
Copy-Item -LiteralPath $Deployed -Destination $backup -Force
Write-Host "Backup: $backup"

$depServer.tree = $tmpServer.tree

$tree = $tmpServer.tree | ConvertFrom-Json
$vars = @($tree.folders[0].variables)
$lines = $vars | ForEach-Object {
    '  {{ "name": "{0}", "path": "{1}" }},' -f $_.name, $_.nodeId
}
$code = "msg.payload = [`n" + ($lines -join "`n") + "`n];`nreturn msg;"
$depFunc = $dep | Where-Object { $_.id -eq "oip-sim-func" } | Select-Object -First 1
if ($depFunc) {
    $depFunc.func = $code
} else {
    throw "Nodo oip-sim-func no encontrado en el desplegado"
}

# Sincroniza los nodos gestionados (write io + botones de velocidad de conveyors)
# desde el template, para que el desplegado nunca se desfase. Se reemplazan los
# que tengan ids oip-sim-* gestionados y se añaden los que falten.
$managedIds = @($tmp | Where-Object { $_.id -like "oip-sim-inject-speed-*" -or $_.id -in @("oip-sim-write-io","oip-sim-inject-loop","oip-sim-func-control","oip-sim-io") } | ForEach-Object { $_.id })
if ($managedIds.Count) {
    $dep = @($dep | Where-Object { $_.id -notin $managedIds })
    $tabId = $depServer.z
    $managedNodes = @($tmp | Where-Object { $_.id -in $managedIds } | ForEach-Object {
        $n = $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $n.z = $tabId
        $n
    })
    $dep = @($dep) + $managedNodes
    Write-Host "Nodos gestionados (velocidad conveyors) sincronizados: $($managedNodes.Count)"
}

if ($RemoveTestNodes) {
    $junk = @("inject-read-all-tags","func-build-read-payload","opcua-server-io-read-all",
              "debug-write-all","inject-a2-1","inject-a2-2","opcua-server-io-write-a2")
    $removed = @($dep | Where-Object { $_.id -in $junk })
    $dep = @($dep | Where-Object { $_.id -notin $junk })
    if ($removed.Count) { Write-Host "Nodos de prueba eliminados: $($removed.Count)" }
}

$json = $dep | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $Deployed), $json, $utf8)

Write-Host "OK: tree ($($vars.Count) variables) y oip-sim-func ($($vars.Count) tags) sincronizados en $Deployed"
Write-Host "RECUERDA: reinicia el servicio Node-RED para que cargue el flujo."
