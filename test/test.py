# SPDX-License-Identifier: Apache-2.0
# Cocotb test for TinyTapeout VGA patterns
#
# Wichtig: tb.v bleibt unverändert. Wir greifen NUR auf Top-Level-Signale zu:
# dut.clk, dut.rst_n, dut.ena, dut.ui_in, dut.uo_out, dut.uio_in
#
# Ablauf:
#  - 25 MHz Takt starten (40 ns)
#  - Reset und Enable setzen
#  - HSYNC-Breite und Zeilenperiode prüfen
#  - kleines Vorschaubild (200x150) als frame_200x150.ppm erzeugen

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# VGA 640x480@60 (pixel clock ~25.175 MHz)
H_TOTAL, V_TOTAL = 800, 525
H_VISIBLE, V_VISIBLE = 640, 480
H_SYNC, H_FP, H_BP = 96, 16, 48
V_SYNC, V_FP, V_BP = 2, 10, 33

def _bit(val, idx):
    return (int(val) >> idx) & 1

@cocotb.test()
async def test_vga_timing_and_snapshot(dut):
    dut._log.info("Start VGA timing & snapshot test (tb.v unverändert)")

    # ~25 MHz Takt (40 ns Periode)
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())

    # Inputs initialisieren
    dut.ena.value   = 1        # Projekt aktiv
    dut.ui_in.value = 3        # Mode 0 (0..5 möglich); ui_in[7:3] Palette
    dut.uio_in.value = 0

    # Reset-Sequenz
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # ---------- HSYNC prüfen ----------
    # In unserem Mapping ist uo_out[7] = HSYNC (low-aktiv)
    # Warte auf fallende Flanke (1->0)
    last = _bit(dut.uo_out.value, 7)
    while True:
        await RisingEdge(dut.clk)
        cur = _bit(dut.uo_out.value, 7)
        if last == 1 and cur == 0:
            break
        last = cur

    # Low-Dauer zählen und Gesamtperiode bestimmen
    low = 0
    total = 0
    last = 0  # wir sind aktuell im Low
    while True:
        await RisingEdge(dut.clk)
        cur = _bit(dut.uo_out.value, 7)
        total += 1
        if cur == 0:
            low += 1
        if last == 0 and cur == 1:   # Ende Low
            break
        last = cur

    # Bis zur nächsten fallenden Flanke -> eine komplette Zeilenperiode
    while True:
        await RisingEdge(dut.clk)
        cur = _bit(dut.uo_out.value, 7)
        total += 1
        if last == 1 and cur == 0:
            break
        last = cur

    assert abs(low - H_SYNC) <= 1, f"HSYNC low width {low}, expected {H_SYNC}"
    assert abs(total - H_TOTAL) <= 2, f"HSYNC period {total}, expected {H_TOTAL}"
    dut._log.info(f"HSYNC ok: low={low}, period={total}")

    # ---------- Mini-Snapshot (200x150) ----------
    # uo_out Mapping (Erwartung aus dem Design):
    # [0]=R1 [1]=G1 [2]=B1 [3]=VSYNC_n [4]=R0 [5]=G0 [6]=B0 [7]=HSYNC_n
    w, hgt = 200, 150
    pixels = []

    # grob auf Frame-Beginn warten: VSYNC low
    for _ in range(H_TOTAL * V_TOTAL * 2):
        await RisingEdge(dut.clk)
        if _bit(dut.uo_out.value, 3) == 0:
            break

    x = y = 0
    for _ in range(H_TOTAL * V_TOTAL):
        await RisingEdge(dut.clk)

        # 2-Bit je Farbe rekonstruieren (gewichtete Stufen 85 / 170)
        r = (_bit(dut.uo_out.value, 0) * 170) + (_bit(dut.uo_out.value, 4) * 85)
        g = (_bit(dut.uo_out.value, 1) * 170) + (_bit(dut.uo_out.value, 5) * 85)
        b = (_bit(dut.uo_out.value, 2) * 170) + (_bit(dut.uo_out.value, 6) * 85)

        if x < w and y < hgt:
            pixels.append((r, g, b))

        x += 1
        if x == H_TOTAL:
            x = 0
            y += 1
            if y == hgt:
                break

    with open("frame_200x150.ppm", "wb") as f:
        f.write(f"P6 {w} {hgt} 255\n".encode())
        f.write(bytes([c for (r, g, b) in pixels for c in (r, g, b)]))

    dut._log.info("Generated frame_200x150.ppm")

    # Optional: hier könntest du weitere Modi testen:
    # z.B. dut.ui_in.value = 4; und noch ein Bild erzeugen.
