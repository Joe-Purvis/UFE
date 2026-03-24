// -----------------------------------------------------------------------------
// LL5k_tb_WIP.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for LL5k_WIP UART register file.
//
// What this TB proves (via real UART stimulus at BAUD):
//   - Basic protocol integrity (SYNC + CHK)
//   - ID (0x00) and VERSION (0x01) readback
//   - Failsafe constraints:
//        1) RX_START (0x23) >= PZT_CLAMP_STOP_TIME (0x22) + 1
//        2) RX_STOP  (0x24) >= RX_START (0x23) + 1
//
// Protocol:
//   Request : 0x55 OP ADDR DATA CHK
//   Response: 0x56 STATUS ADDR DATA CHK
//   CHK = XOR of first 4 bytes
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module LL5k_tb_WIP;

     localparam integer CLK_HZ = 12_000_000;
     localparam integer BAUD   = 9_600;

     localparam real CLK_PER_NS = 1e9 / CLK_HZ;
     localparam real BIT_NS     = 1e9 / BAUD;

     logic clk;
     logic uart_rx;
     wire  uart_tx;

     LL5k_WIP
          #(
               .CLK_HZ(CLK_HZ),
               .BAUD(BAUD)
          )
     dut
          (
               .clk(clk),
               .uart_rx(uart_rx),
               .uart_tx(uart_tx)
          );

     initial
     begin
          clk = 1'b0;
          forever #(CLK_PER_NS/2.0) clk = ~clk;
     end

     task automatic uart_send_byte(input byte b);
          integer i;
          begin
               // start bit
               uart_rx = 1'b0;
               #(BIT_NS);

               // data bits LSB first
               for (i = 0; i < 8; i = i + 1)
               begin
                    uart_rx = b[i];
                    #(BIT_NS);
               end

               // stop bit
               uart_rx = 1'b1;
               #(BIT_NS);
          end
     endtask

     task automatic uart_recv_byte(output byte b);
          integer i;
          begin
               // wait for start
               wait (uart_tx == 1'b0);
               #(BIT_NS*0.5);

               // sample bits
               for (i = 0; i < 8; i = i + 1)
               begin
                    #(BIT_NS);
                    b[i] = uart_tx;
               end

               // stop bit
               #(BIT_NS);
               if (uart_tx !== 1'b1)
               begin
                    $display("TB: FAIL - stop bit not high.");
                    $finish;
               end
          end
     endtask

     function automatic byte chk4(input byte b0, input byte b1, input byte b2, input byte b3);
          begin
               chk4 = b0 ^ b1 ^ b2 ^ b3;
          end
     endfunction

     task automatic send_req(input byte op, input byte addr, input byte data);
          byte chk;
          begin
               chk = chk4(8'h55, op, addr, data);
               uart_send_byte(8'h55);
               uart_send_byte(op);
               uart_send_byte(addr);
               uart_send_byte(data);
               uart_send_byte(chk);
          end
     endtask

     task automatic recv_resp(output byte status, output byte addr, output byte data);
          byte sync;
          byte chk;
          byte chk_calc;
          begin
               uart_recv_byte(sync);
               uart_recv_byte(status);
               uart_recv_byte(addr);
               uart_recv_byte(data);
               uart_recv_byte(chk);

               if (sync !== 8'h56)
               begin
                    $display("TB: FAIL - bad response SYNC 0x%02X", sync);
                    $finish;
               end

               chk_calc = chk4(sync, status, addr, data);
               if (chk !== chk_calc)
               begin
                    $display("TB: FAIL - bad response CHK got 0x%02X exp 0x%02X", chk, chk_calc);
                    $finish;
               end

               if (status[0] !== 1'b0)
               begin
                    $display("TB: FAIL - status error st=0x%02X", status);
                    $finish;
               end
          end
     endtask

     task automatic write8(input byte addr, input byte data);
          byte st, ra, rd;
          begin
               $display("TB: WRITE8  addr=0x%02X data=0x%02X", addr, data);
               send_req(8'h02, addr, data);
               recv_resp(st, ra, rd);

               if (ra !== addr)
               begin
                    $display("TB: FAIL - write8 addr mismatch got 0x%02X exp 0x%02X", ra, addr);
                    $finish;
               end
          end
     endtask

     task automatic read8(input byte addr, output byte data);
          byte st, ra, rd;
          begin
               $display("TB: READ8   addr=0x%02X", addr);
               send_req(8'h01, addr, 8'h00);
               recv_resp(st, ra, rd);

               if (ra !== addr)
               begin
                    $display("TB: FAIL - read8 addr mismatch got 0x%02X exp 0x%02X", ra, addr);
                    $finish;
               end

               data = rd;
               $display("TB: READ8   addr=0x%02X -> 0x%02X", addr, data);
          end
     endtask

     initial
     begin
          byte v_id;
          byte v_ver;
          byte v_start;
          byte v_stop;

          uart_rx = 1'b1;

          // Allow POR to release (~1ms in DUT); wait 2ms
          $display("TB: Waiting for POR release...");
          #(2_000_000);
          $display("TB: POR window elapsed, starting tests.");

          // Basic identity reads (verifies ID/VERSION registers exist and UART RX/TX works)
          read8(8'h00, v_id);
          if (v_id !== 8'h01)
          begin
               $display("TB: FAIL - ID mismatch got 0x%02X exp 0x01", v_id);
               $finish;
          end

          read8(8'h01, v_ver);
          if (v_ver !== 8'h01)
          begin
               $display("TB: FAIL - VERSION mismatch got 0x%02X exp 0x01", v_ver);
               $finish;
          end

          // Set PZT clamp stop to 0x10
          write8(8'h22, 8'h10);

          // Write RX_START = 0x10 (should clamp to 0x11)
          write8(8'h23, 8'h10);
          read8(8'h23, v_start);
          if (v_start !== 8'h11)
          begin
               $display("TB: FAIL - RX_START clamp not applied. got 0x%02X exp 0x11", v_start);
               $finish;
          end

          // Write RX_STOP = 0x11 (should clamp to 0x12 because STOP must be > START)
          write8(8'h24, 8'h11);
          read8(8'h24, v_stop);
          if (v_stop !== 8'h12)
          begin
               $display("TB: FAIL - RX_STOP clamp not applied. got 0x%02X exp 0x12", v_stop);
               $finish;
          end

          // Valid write RX_STOP = 0x20 should be accepted
          write8(8'h24, 8'h20);
          read8(8'h24, v_stop);
          if (v_stop !== 8'h20)
          begin
               $display("TB: FAIL - RX_STOP write not accepted. got 0x%02X exp 0x20", v_stop);
               $finish;
          end

          // Move RX_START forward to 0x1F; RX_STOP should remain >= RX_START+1 (still 0x20 OK)
          write8(8'h23, 8'h1F);
          read8(8'h23, v_start);
          read8(8'h24, v_stop);

          if (v_start !== 8'h1F)
          begin
               $display("TB: FAIL - RX_START write not accepted. got 0x%02X exp 0x1F", v_start);
               $finish;
          end

          if (v_stop !== 8'h20)
          begin
               $display("TB: FAIL - RX_STOP unexpectedly changed. got 0x%02X exp 0x20", v_stop);
               $finish;
          end

          $display("TB: PASS - ID/VERSION and RX_START/RX_STOP failsafe clamps verified.");
          $finish;
     end

endmodule
