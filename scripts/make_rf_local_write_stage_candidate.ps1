param(
  [string]$Source = 'D:\PDS\project\NAX\rtl\NaxRiscvContest.v',
  [string]$Output = 'D:\PDS\project\NAX\rtl\NaxRiscvContest_rf_local_write_stage_20261006.v'
)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Source -Raw
$begin = $text.IndexOf('  // Replicate the four-write register file at the execution-unit boundary.')
$end = $text.IndexOf('  DependencyStorage RfDependencyPlugin_logic_forRf_integer_impl', $begin)
if ($begin -lt 0 -or $end -lt 0) { throw 'RF replication block was not found' }
$block = $text.Substring($begin, $end - $begin)
$copies = @('alu0','alu1','eu0')
$fields = @(
  @{ Name='valid'; Width=''; Suffix='valid' },
  @{ Name='address'; Width='[5:0]'; Suffix='address[5:0]' },
  @{ Name='data'; Width='[31:0]'; Suffix='data[31:0]' },
  @{ Name='robId'; Width='[4:0]'; Suffix='robId[4:0]' }
)

$decl = "  // Stage only the RF write payload for ports 0..2 locally.  The architectural`r`n"
$decl += "  // bypass signals remain on the original same-cycle path; the staged values`r`n"
$decl += "  // are consumed by the physical RF on the following edge.`r`n"
foreach ($copy in $copies) {
  foreach ($w in 0..2) {
    foreach ($field in $fields) {
      $width = if ($field.Width) { " $($field.Width)" } else { '' }
      $name = "rf_${copy}_w${w}_$($field.Name)"
      $decl += "  (* keep, syn_keep *) reg$width $name /* synthesis syn_keep = 1 */;`r`n"
    }
  }
  foreach ($field in $fields) {
    $width = if ($field.Width) { " $($field.Width)" } else { '' }
    $name = "rf_${copy}_w3_$($field.Name)"
    $src = "integer_RegFilePlugin_logic_writeMerges_3_bus_$($field.Suffix)"
    $decl += "  (* keep, syn_keep *) wire$width $name /* synthesis syn_keep = 1 */ = $src;`r`n"
  }
}
$decl += "  always @(posedge clk) begin`r`n"
$decl += "    if (reset) begin`r`n"
foreach ($copy in $copies) {
  foreach ($w in 0..2) {
    $decl += "      rf_${copy}_w${w}_valid <= 1'b0;`r`n"
    $decl += "      rf_${copy}_w${w}_address <= 6'd0; rf_${copy}_w${w}_data <= 32'd0; rf_${copy}_w${w}_robId <= 5'd0;`r`n"
  }
}
$decl += "    end else begin`r`n"
foreach ($copy in $copies) {
  foreach ($w in 0..2) {
    $decl += "      rf_${copy}_w${w}_valid <= integer_RegFilePlugin_logic_writeMerges_${w}_bus_valid;`r`n"
    $decl += "      rf_${copy}_w${w}_address <= integer_RegFilePlugin_logic_writeMerges_${w}_bus_address[5:0];`r`n"
    $decl += "      rf_${copy}_w${w}_data <= integer_RegFilePlugin_logic_writeMerges_${w}_bus_data[31:0];`r`n"
    $decl += "      rf_${copy}_w${w}_robId <= integer_RegFilePlugin_logic_writeMerges_${w}_bus_robId[4:0];`r`n"
  }
}
$decl += "    end`r`n  end`r`n"

foreach ($copy in $copies) {
  $marker = "  RegFileAsync integer_RegFilePlugin_logic_regfile_fpga_$copy ("
  $s = $block.IndexOf($marker)
  if ($s -lt 0) { throw "RF copy not found: $copy" }
  $e = $block.IndexOf("`r`n  RegFileAsync ", $s + $marker.Length)
  if ($e -lt 0) { $e = $block.Length }
  $section = $block.Substring($s, $e - $s)
  for ($w = 0; $w -le 3; $w++) {
    foreach ($field in $fields) {
      $old = "integer_RegFilePlugin_logic_writeMerges_${w}_bus_$($field.Suffix)"
      $new = "rf_${copy}_w${w}_$($field.Name)"
      $section = $section.Replace($old, $new)
    }
  }
  $block = $block.Substring(0, $s) + $section + $block.Substring($e)
}
$newText = $text.Substring(0, $begin) + $decl + $block + $text.Substring($end)
Set-Content -LiteralPath $Output -Value $newText -Encoding ascii
Write-Output "Generated $Output"
