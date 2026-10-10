param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$text = [System.IO.File]::ReadAllText((Resolve-Path $Source))

$marker = '  wire                EU0_ExecutionUnitBase_pipeline_rfReads_integer_RS1_valid;'
if (-not $text.Contains($marker)) {
    throw "EU0 RF declaration marker not found: $marker"
}

$aliases = @'
  // Same-cycle, EU0-local copies of the complete early-bypass payload.
  // These aliases preserve valid/address/data together and do not add a pipeline stage.
  (* keep, syn_keep *) wire        eu0_alu0_shared_valid = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_alu0_shared_address = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address;
  (* keep, syn_keep *) wire [31:0] eu0_alu0_shared_data = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data;
  (* keep, syn_keep *) wire        eu0_alu0_dedicated_valid = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_alu0_dedicated_address = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address;
  (* keep, syn_keep *) wire [31:0] eu0_alu0_dedicated_data = ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data;
  (* keep, syn_keep *) wire        eu0_alu1_shared_valid = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_alu1_shared_address = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address;
  (* keep, syn_keep *) wire [31:0] eu0_alu1_shared_data = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data;
  (* keep, syn_keep *) wire        eu0_alu1_dedicated_valid = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_alu1_dedicated_address = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address;
  (* keep, syn_keep *) wire [31:0] eu0_alu1_dedicated_data = ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data;
  (* keep, syn_keep *) wire        eu0_wb0_valid = integer_RegFilePlugin_logic_writeMerges_0_bypass_port_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_wb0_address = integer_RegFilePlugin_logic_writeMerges_0_bypass_port_address;
  (* keep, syn_keep *) wire [31:0] eu0_wb0_data = integer_RegFilePlugin_logic_writeMerges_0_bypass_port_data;
  (* keep, syn_keep *) wire        eu0_wb1_valid = integer_RegFilePlugin_logic_writeMerges_1_bypass_port_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_wb1_address = integer_RegFilePlugin_logic_writeMerges_1_bypass_port_address;
  (* keep, syn_keep *) wire [31:0] eu0_wb1_data = integer_RegFilePlugin_logic_writeMerges_1_bypass_port_data;
  (* keep, syn_keep *) wire        eu0_wb2_valid = integer_RegFilePlugin_logic_writeMerges_2_bypass_port_valid;
  (* keep, syn_keep *) wire [5:0]  eu0_wb2_address = integer_RegFilePlugin_logic_writeMerges_2_bypass_port_address;
  (* keep, syn_keep *) wire [31:0] eu0_wb2_data = integer_RegFilePlugin_logic_writeMerges_2_bypass_port_data;
'@
$text = $text.Replace($marker, $aliases + "`r`n" + $marker)

$map = [ordered]@{
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid' = 'eu0_alu0_shared_valid'
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address' = 'eu0_alu0_shared_address'
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data' = 'eu0_alu0_shared_data'
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid' = 'eu0_alu0_dedicated_valid'
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address' = 'eu0_alu0_dedicated_address'
    'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data' = 'eu0_alu0_dedicated_data'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid' = 'eu0_alu1_shared_valid'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address' = 'eu0_alu1_shared_address'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data' = 'eu0_alu1_shared_data'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid' = 'eu0_alu1_dedicated_valid'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address' = 'eu0_alu1_dedicated_address'
    'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data' = 'eu0_alu1_dedicated_data'
    'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_valid' = 'eu0_wb0_valid'
    'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_address' = 'eu0_wb0_address'
    'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_data' = 'eu0_wb0_data'
    'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_valid' = 'eu0_wb1_valid'
    'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_address' = 'eu0_wb1_address'
    'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_data' = 'eu0_wb1_data'
    'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_valid' = 'eu0_wb2_valid'
    'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_address' = 'eu0_wb2_address'
    'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_data' = 'eu0_wb2_data'
}

function Replace-Scoped([string]$body) {
    foreach ($key in $map.Keys) { $body = $body.Replace($key, [string]$map[$key]) }
    return $body
}

# Replace only EU0 RF read muxes. ALU0/ALU1 muxes remain untouched.
$muxMarkers = @(
    'case(_zz_EU0_ExecutionUnitBase_pipeline_rfReads_integer_RS1_data_4)',
    'case(_zz_EU0_ExecutionUnitBase_pipeline_rfReads_integer_RS2_data_4)'
)
foreach ($markerText in $muxMarkers) {
    $casePos = $text.IndexOf($markerText)
    if ($casePos -lt 0) { throw "EU0 mux marker not found: $markerText" }
    $start = $text.LastIndexOf('  always @(*) begin', $casePos)
    if ($start -lt 0) { throw "EU0 mux always block not found: $markerText" }
    $next = $text.IndexOf('  always @(*) begin', $casePos + $markerText.Length)
    if ($next -lt 0) { throw 'EU0 mux block terminator not found' }
    $head = $text.Substring(0, $start)
    $block = $text.Substring($start, $next - $start)
    $tail = $text.Substring($next)
    $text = $head + (Replace-Scoped $block) + $tail
}

# Replace only EU0 valid/address comparator logic, preserving the complete payload aliases.
$cmpStartMarker = '  assign _zz_when_RegFilePlugin_l327_24'
$cmpStart = $text.IndexOf($cmpStartMarker)
if ($cmpStart -lt 0) { throw "EU0 comparator start marker not found: $cmpStartMarker" }
$cmpEndMarker = '  assign integer_write_0_valid'
$cmpEnd = $text.IndexOf($cmpEndMarker, $cmpStart)
if ($cmpEnd -lt 0) { throw "EU0 comparator end marker not found: $cmpEndMarker" }
$head = $text.Substring(0, $cmpStart)
$cmp = $text.Substring($cmpStart, $cmpEnd - $cmpStart)
$tail = $text.Substring($cmpEnd)
$text = $head + (Replace-Scoped $cmp) + $tail

$outputPath = [System.IO.Path]::GetFullPath($Output)
$outDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllText($outputPath, $text, [System.Text.Encoding]::ASCII)
Write-Output "Wrote $outputPath"
