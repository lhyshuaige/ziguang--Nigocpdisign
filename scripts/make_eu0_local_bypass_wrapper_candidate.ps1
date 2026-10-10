param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$baseCandidate = Join-Path ([System.IO.Path]::GetTempPath()) 'NaxRiscvContest_eu0_local_bypass_base.v'
& (Join-Path $PSScriptRoot 'make_eu0_local_bypass_candidate.ps1') -Source $Source -Output $baseCandidate | Out-Null
$text = [System.IO.File]::ReadAllText($baseCandidate)

$signals = [ordered]@{
  'eu0_alu0_shared_valid' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid'
  'eu0_alu0_shared_address' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address'
  'eu0_alu0_shared_data' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data'
  'eu0_alu0_dedicated_valid' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid'
  'eu0_alu0_dedicated_address' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address'
  'eu0_alu0_dedicated_data' = 'ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data'
  'eu0_alu1_shared_valid' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid'
  'eu0_alu1_shared_address' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address'
  'eu0_alu1_shared_data' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data'
  'eu0_alu1_dedicated_valid' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid'
  'eu0_alu1_dedicated_address' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address'
  'eu0_alu1_dedicated_data' = 'ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data'
  'eu0_wb0_valid' = 'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_valid'
  'eu0_wb0_address' = 'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_address'
  'eu0_wb0_data' = 'integer_RegFilePlugin_logic_writeMerges_0_bypass_port_data'
  'eu0_wb1_valid' = 'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_valid'
  'eu0_wb1_address' = 'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_address'
  'eu0_wb1_data' = 'integer_RegFilePlugin_logic_writeMerges_1_bypass_port_data'
  'eu0_wb2_valid' = 'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_valid'
  'eu0_wb2_address' = 'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_address'
  'eu0_wb2_data' = 'integer_RegFilePlugin_logic_writeMerges_2_bypass_port_data'
}

# Turn the kept aliases into outputs of explicit, same-cycle module boundaries.
foreach ($name in $signals.Keys) {
    $pattern = "  \(\* keep, syn_keep \*\) wire(?<width>[^\r\n]*) $name = [^;]+;"
    $replacement = '  (* keep, syn_keep *) wire${width} ' + $name + ';'
    $text = [regex]::Replace($text, $pattern, $replacement)
}

$inst = @'
  // Explicit combinational boundaries prevent the seven EU0 payloads from being
  // merged back into the global bypass nets during hierarchy-preserving synthesis.
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_alu0_shared (
    .in_valid(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid),
    .in_address(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address),
    .in_data(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data),
    .out_valid(eu0_alu0_shared_valid), .out_address(eu0_alu0_shared_address), .out_data(eu0_alu0_shared_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_alu0_dedicated (
    .in_valid(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid),
    .in_address(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address),
    .in_data(ALU0_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data),
    .out_valid(eu0_alu0_dedicated_valid), .out_address(eu0_alu0_dedicated_address), .out_data(eu0_alu0_dedicated_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_alu1_shared (
    .in_valid(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_valid),
    .in_address(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_address),
    .in_data(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_shared_bypass_data),
    .out_valid(eu0_alu1_shared_valid), .out_address(eu0_alu1_shared_address), .out_data(eu0_alu1_shared_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_alu1_dedicated (
    .in_valid(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_valid),
    .in_address(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_address),
    .in_data(ALU1_ExecutionUnitBase_pipeline_earlyBypasses_0_dedicated_0_bypass_data),
    .out_valid(eu0_alu1_dedicated_valid), .out_address(eu0_alu1_dedicated_address), .out_data(eu0_alu1_dedicated_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_wb0 (
    .in_valid(integer_RegFilePlugin_logic_writeMerges_0_bypass_port_valid),
    .in_address(integer_RegFilePlugin_logic_writeMerges_0_bypass_port_address),
    .in_data(integer_RegFilePlugin_logic_writeMerges_0_bypass_port_data),
    .out_valid(eu0_wb0_valid), .out_address(eu0_wb0_address), .out_data(eu0_wb0_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_wb1 (
    .in_valid(integer_RegFilePlugin_logic_writeMerges_1_bypass_port_valid),
    .in_address(integer_RegFilePlugin_logic_writeMerges_1_bypass_port_address),
    .in_data(integer_RegFilePlugin_logic_writeMerges_1_bypass_port_data),
    .out_valid(eu0_wb1_valid), .out_address(eu0_wb1_address), .out_data(eu0_wb1_data));
  (* keep_hierarchy = "yes", syn_keep *) pgl50h_eu0_bypass_payload_copy u_eu0_wb2 (
    .in_valid(integer_RegFilePlugin_logic_writeMerges_2_bypass_port_valid),
    .in_address(integer_RegFilePlugin_logic_writeMerges_2_bypass_port_address),
    .in_data(integer_RegFilePlugin_logic_writeMerges_2_bypass_port_data),
    .out_valid(eu0_wb2_valid), .out_address(eu0_wb2_address), .out_data(eu0_wb2_data));
'@
$marker = '  wire                EU0_ExecutionUnitBase_pipeline_rfReads_integer_RS1_valid;'
if (-not $text.Contains($marker)) { throw 'EU0 marker not found for payload instances' }
$text = $text.Replace($marker, $inst + "`r`n" + $marker)

$module = @'

(* keep_hierarchy = "yes" *) module pgl50h_eu0_bypass_payload_copy(
  input  wire        in_valid,
  input  wire [5:0]  in_address,
  input  wire [31:0] in_data,
  output wire        out_valid,
  output wire [5:0]  out_address,
  output wire [31:0] out_data
);
  (* keep, syn_keep *) assign out_valid = in_valid;
  (* keep, syn_keep *) assign out_address = in_address;
  (* keep, syn_keep *) assign out_data = in_data;
endmodule
'@
$text += $module

$outputPath = [System.IO.Path]::GetFullPath($Output)
$outDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllText($outputPath, $text, [System.Text.Encoding]::ASCII)
Remove-Item -LiteralPath $baseCandidate -Force -ErrorAction SilentlyContinue
Write-Output "Wrote $outputPath"
