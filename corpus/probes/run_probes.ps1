# MoonCalc semantic probes against real desktop Excel (COM, headless).
# Reads a TSV probe table, evaluates each case, writes JSON results.
#
# TSV columns: id <TAB> anchor <TAB> mode <TAB> rows <TAB> cols <TAB> formula <TAB> setup
#   mode  : normal | dynamic | cse
#   rows/cols : cse target range size (1 for normal/dynamic)
#   setup : ADDR=spec;ADDR=spec  with spec n:1.5 t:abc b:1 e:#N/A f:=A1+1 blank
# Blank lines and lines starting with # are ignored.
param(
  [Parameter(Mandatory=$true)][string]$SpecPath,
  [Parameter(Mandatory=$true)][string]$OutPath
)
$ErrorActionPreference = "Stop"

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$xl.ScreenUpdating = $false
$xl.AutomationSecurity = 3   # msoAutomationSecurityForceDisable (no macros)
$xl.EnableEvents = $false
$wb = $null
$results = New-Object System.Collections.ArrayList

function Err-Name([int]$code) {
  switch ($code) {
    -2146826281 { return "#DIV/0!" }
    -2146826246 { return "#N/A" }
    -2146826259 { return "#NAME?" }
    -2146826288 { return "#NULL!" }
    -2146826252 { return "#NUM!" }
    -2146826265 { return "#REF!" }
    -2146826273 { return "#VALUE!" }
    -2146826182 { return "#CALC!" }
    -2146826243 { return "#SPILL!" }
    default { return ("#ERRCODE" + $code + "!") }
  }
}

function Read-Cell($cell) {
  $v = $cell.Value2
  if ($null -eq $v) { return @{ t = "blank" } }
  if ($v -is [System.Array]) { return (Read-Range $cell) }
  if ($v -is [System.Int32]) {
    $code = [int]$v
    if ($code -lt 0) { return @{ t = "error"; v = (Err-Name $code) } }
    return @{ t = "number"; v = [double]$code }
  }
  $ty = $v.GetType().Name
  if ($ty -eq "Boolean") { return @{ t = "bool"; v = [bool]$v } }
  if ($ty -eq "String") { return @{ t = "text"; v = [string]$v } }
  if ($ty -eq "Double" -or $ty -eq "Int64" -or $ty -eq "Decimal") {
    return @{ t = "number"; v = [double]$v }
  }
  if ($cell.Text -match '^#') { return @{ t = "error"; v = [string]$cell.Text } }
  return @{ t = "text"; v = [string]$v }
}

function Read-Range($rng) {
  $v = $rng.Value2
  if (-not ($v -is [System.Array])) { return (Read-Cell $rng) }
  $rows = $v.GetLength(0)
  $cols = $v.GetLength(1)
  $out = New-Object System.Collections.ArrayList
  for ($i = 1; $i -le $rows; $i++) {
    $row = New-Object System.Collections.ArrayList
    for ($j = 1; $j -le $cols; $j++) {
      $c = $rng.Cells.Item($i, $j)
      [void]$row.Add((Read-Cell $c))
    }
    [void]$out.Add($row)
  }
  return @{ t = "array"; rows = $rows; cols = $cols; v = $out }
}

function Parse-Spec([string]$s) {
  if ($s.Length -ge 2 -and $s.Substring(0,2) -eq "n:") { return @{ kind="num"; v=[double]$s.Substring(2) } }
  if ($s.Length -ge 2 -and $s.Substring(0,2) -eq "t:") { return @{ kind="text"; v=$s.Substring(2) } }
  if ($s.Length -ge 2 -and $s.Substring(0,2) -eq "b:") { return @{ kind="bool"; v=($s.Substring(2) -eq "1") } }
  if ($s.Length -ge 2 -and $s.Substring(0,2) -eq "e:") { return @{ kind="err"; v=$s.Substring(2) } }
  if ($s.Length -ge 3 -and $s.Substring(0,3) -eq "f2:") { return @{ kind="formula2"; v=$s.Substring(3) } }
  if ($s.Length -ge 4 -and $s.Substring(0,4) -eq "cse:") { return @{ kind="formulaarray"; v=$s.Substring(4) } }
  if ($s.Length -ge 2 -and $s.Substring(0,2) -eq "f:") { return @{ kind="formula"; v=$s.Substring(2) } }
  if ($s -eq "blank") { return @{ kind="blank" } }
  throw ("bad setup spec: " + $s)
}

function Split-Setup([string]$s) {
  $items = New-Object System.Collections.ArrayList
  $buf = ""
  $depth = 0
  foreach ($ch in $s.ToCharArray()) {
    if ($ch -eq '{') { $depth++ }
    elseif ($ch -eq '}') { if ($depth -gt 0) { $depth-- } }
    if ($ch -eq ';' -and $depth -eq 0) {
      [void]$items.Add($buf)
      $buf = ""
    } else {
      $buf = $buf + $ch
    }
  }
  [void]$items.Add($buf)
  return $items
}

function Apply-Setup($ws, [string]$setup) {
  if ([string]::IsNullOrEmpty($setup)) { return }
  foreach ($item in Split-Setup $setup) {
    if ([string]::IsNullOrEmpty($item)) { continue }
    $eq = $item.IndexOf("=")
    if ($eq -lt 1) { throw ("bad setup item: " + $item) }
    $addr = $item.Substring(0, $eq)
    $spec = Parse-Spec $item.Substring($eq + 1)
    $rng = $ws.Range($addr)
    switch ($spec.kind) {
      "num"     { $rng.Value2 = $spec.v }
      "text"    { $rng.Value2 = $spec.v }
      "bool"    { $rng.Value2 = $spec.v }
      "blank"   { [void]$rng.ClearContents() }
      "err"     { $rng.Formula = "=" + $spec.v }
      "formula" { $rng.Formula = $spec.v }
      "formula2" { $rng.Formula2 = $spec.v }
      "formulaarray" { $rng.FormulaArray = $spec.v }
    }
  }
}

function Add-Result($rec) {
  [void]$results.Add([pscustomobject]$rec)
}

$lines = Get-Content -Path $SpecPath -Encoding UTF8
$wb = $xl.Workbooks.Add()
$ws = $wb.Worksheets.Item(1)
$ws.Name = "Probe"
$xl.Calculate()

foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  if ($line.StartsWith("#")) { continue }
  $parts = $line.Split("`t")
  if ($parts.Count -eq 6) { $parts += "" }
  if ($parts.Count -lt 7) { throw ("bad probe line: " + $line) }
  $id = $parts[0]; $anchor = $parts[1]; $mode = $parts[2]
  $nrows = [int]$parts[3]; $ncols = [int]$parts[4]
  $formula = $parts[5]; $setup = $parts[6]
  $rec = @{ id = $id; anchor = $anchor; mode = $mode; formula = $formula; setup = $setup }
  try {
    [void]$ws.Cells.Clear()
    Apply-Setup $ws $setup
    $rng = $ws.Range($anchor)
    $enteredRange = $null
    if ($mode -eq "cse") {
      if ($nrows -gt 1 -or $ncols -gt 1) {
        $end = $ws.Cells.Item($rng.Row + $nrows - 1, $rng.Column + $ncols - 1)
        $rng = $ws.Range($ws.Cells.Item($rng.Row, $rng.Column), $end)
      }
      $enteredRange = $rng
      $rng.FormulaArray = $formula
    } elseif ($mode -eq "dynamic") {
      $rng.Formula2 = $formula
    } else {
      $rng.Formula = $formula
    }
    $xl.Calculate()
    $anchorCell = $ws.Range($parts[1])
    $rec.entered = $anchorCell.Formula
    $rec.hasArray = [bool]$anchorCell.HasArray
    $rec.hasSpill = [bool]$anchorCell.HasSpill
    if ($anchorCell.HasSpill) {
      try { $rec.spillRange = $anchorCell.SpillingToRange.Address($false, $false) } catch { $rec.spillRange = "?" }
      try { $rec.value = Read-Range $anchorCell.SpillingToRange } catch { $rec.value = Read-Cell $anchorCell }
    } else {
      if ($null -ne $enteredRange) { $rec.value = Read-Range $enteredRange }
      else { $rec.value = Read-Range $anchorCell }
    }
  } catch {
    $rec.entered = $null
    $rec.error = $_.Exception.Message
    try { $rec.excelError = $xl.GetType().InvokeMember("Error", "GetProperty", $null, $xl, @($true)) } catch {}
  }
  Add-Result $rec
}

$json = ($results | ConvertTo-Json -Depth 12) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))
$wb.Close($false)
$xl.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
Write-Output ("wrote " + $OutPath)
