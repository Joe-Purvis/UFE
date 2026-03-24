// ------------------------------------------------------------
// Testbench: ll5k UART pin-level verification (9600 8N1)
// Checks:
//   0x00 ID      (RO) = 0x01
//   0x01 VERSION (RO) = 0x01
//   0x02 CONTROL (RW) + interlocks + POR (self-clearing)
// ------------------------------------------------------------
// Formatting: Whitesmiths braces + 5-space indent
// ------------------------------------------------------------
`timescale 1ps/1ps

module tb_ll5k_uart
     ;

     localparam integer CLK_HZ = 12_000_000;
     localparam integer BAUD   = 9_600;

     localparam longint CLK_HALF_PS = 41_667;
     localparam longint BIT_PS      = 104_166_667;

     localparam longint RESP_START_TIMEOUT_PS = (BIT_PS * 80);

     localparam [7:0] ID_ADDR      = 8'h00;
     localparam [7:0] ID_VALUE     = 8'h01;

     localparam [7:0] VER_ADDR     = 8'h01;
     localparam [7:0] VER_VALUE    = 8'h01;

     localparam [7:0] CONTROL_ADDR = 8'h02;

     
     localparam [7:0] STATUS_ADDR  = 8'h03;

     localparam [7:0] PZT_CLAMP_START_ADDR = 8'h21;
     localparam [7:0] PZT_CLAMP_START_DFLT = 8'h01;
logic clk;
     logic uart_rx;
     wire  uart_tx;

     ll5k
          #(
               .CLK_HZ(CLK_HZ),
               .BAUD  (BAUD)
          )
     dut
          (
               .clk     (clk),
               .uart_rx (uart_rx),
               .uart_tx (uart_tx)
          );

     initial
     begin
          clk = 1'b0;
          forever
          begin
               #(CLK_HALF_PS) clk = ~clk;
          end
     end

     task automatic uart_host_send_byte(input [7:0] b);
          integer i;
          begin
               uart_rx = 1'b0;
               #(BIT_PS);

               for (i = 0; i < 8; i = i + 1)
               begin
                    uart_rx = b[i];
                    #(BIT_PS);
               end

               uart_rx = 1'b1;
               #(BIT_PS);
          end
     endtask

     task automatic uart_host_recv_byte(output [7:0] b);
          integer i;
          reg stop_bit;
          longint t0;
          begin
               t0 = $time;

               while (uart_tx !== 1'b0)
               begin
                    if (($time - t0) > RESP_START_TIMEOUT_PS)
                    begin
                         $display("TB: FAIL - timeout waiting for UART TX start bit at t=%0t", $time);
                         $finish;
                    end
                    #(BIT_PS / 8);
               end

               #(BIT_PS + (BIT_PS / 2));

               for (i = 0; i < 8; i = i + 1)
               begin
                    b[i] = uart_tx;
                    #(BIT_PS);
               end

               stop_bit = uart_tx;
               if (stop_bit !== 1'b1)
               begin
                    $display("TB: FAIL - stop bit not high (stop_bit=%b) t=%0t", stop_bit, $time);
                    $finish;
               end

               #(BIT_PS / 2);
          end
     endtask

     function automatic [7:0] req_chk(input [7:0] op, input [7:0] addr, input [7:0] data);
          begin
               req_chk = (8'h55 ^ op ^ addr ^ data);
          end
     endfunction

     function automatic [7:0] resp_chk(input [7:0] st, input [7:0] addr, input [7:0] data);
          begin
               resp_chk = (8'h56 ^ st ^ addr ^ data);
          end
     endfunction

     task automatic do_read8_check
          (
               input [7:0] raddr,
               input [7:0] expected_status,
               input [7:0] expected_data
          );
          reg [7:0] b0, b1, b2, b3, b4;
          reg [7:0] op, addr, data, chk;
          begin
               op   = 8'h01;
               addr = raddr;
               data = 8'h00;
               chk  = req_chk(op, addr, data);

               $display("TB: Sending READ8 addr=0x%02X chk=0x%02X", addr, chk);

               uart_host_send_byte(8'h55);
               uart_host_send_byte(op);
               uart_host_send_byte(addr);
               uart_host_send_byte(data);
               uart_host_send_byte(chk);

               $display("TB: Receiving response...");

               uart_host_recv_byte(b0);
               uart_host_recv_byte(b1);
               uart_host_recv_byte(b2);
               uart_host_recv_byte(b3);
               uart_host_recv_byte(b4);

               $display("TB: RX bytes: %02X %02X %02X %02X %02X", b0, b1, b2, b3, b4);

               if (b0 !== 8'h56)
               begin
                    $display("TB: FAIL - SYNC expected 0x56, got 0x%02X", b0);
                    $finish;
               end

               if (b1 !== expected_status)
               begin
                    $display("TB: FAIL - STATUS expected 0x%02X, got 0x%02X", expected_status, b1);
                    $finish;
               end

               if (b2 !== raddr)
               begin
                    $display("TB: FAIL - ADDR expected 0x%02X, got 0x%02X", raddr, b2);
                    $finish;
               end

               if (b3 !== expected_data)
               begin
                    $display("TB: FAIL - DATA expected 0x%02X, got 0x%02X", expected_data, b3);
                    $finish;
               end

               if (b4 !== resp_chk(b1, b2, b3))
               begin
                    $display("TB: FAIL - CHK mismatch got 0x%02X expected 0x%02X", b4, resp_chk(b1, b2, b3));
                    $finish;
               end

               $display("TB: PASS - READ8 0x%02X returned 0x%02X (STATUS=0x%02X)", raddr, b3, b1);

               #(BIT_PS * 3);
          end
     endtask

     task automatic do_write8_check
          (
               input [7:0] waddr,
               input [7:0] wdata,
               input [7:0] expected_status,
               input [7:0] expected_data
          );
          reg [7:0] b0, b1, b2, b3, b4;
          reg [7:0] op, addr, data, chk;
          begin
               op   = 8'h02;
               addr = waddr;
               data = wdata;
               chk  = req_chk(op, addr, data);

               $display("TB: Sending WRITE8 addr=0x%02X data=0x%02X chk=0x%02X", addr, data, chk);

               uart_host_send_byte(8'h55);
               uart_host_send_byte(op);
               uart_host_send_byte(addr);
               uart_host_send_byte(data);
               uart_host_send_byte(chk);

               $display("TB: Receiving response...");

               uart_host_recv_byte(b0);
               uart_host_recv_byte(b1);
               uart_host_recv_byte(b2);
               uart_host_recv_byte(b3);
               uart_host_recv_byte(b4);

               $display("TB: RX bytes: %02X %02X %02X %02X %02X", b0, b1, b2, b3, b4);

               if (b0 !== 8'h56)
               begin
                    $display("TB: FAIL - SYNC expected 0x56, got 0x%02X", b0);
                    $finish;
               end

               if (b1 !== expected_status)
               begin
                    $display("TB: FAIL - STATUS expected 0x%02X, got 0x%02X", expected_status, b1);
                    $finish;
               end

               if (b2 !== waddr)
               begin
                    $display("TB: FAIL - ADDR expected 0x%02X, got 0x%02X", waddr, b2);
                    $finish;
               end

               if (b3 !== expected_data)
               begin
                    $display("TB: FAIL - DATA expected 0x%02X, got 0x%02X", expected_data, b3);
                    $finish;
               end

               if (b4 !== resp_chk(b1, b2, b3))
               begin
                    $display("TB: FAIL - CHK mismatch got 0x%02X expected 0x%02X", b4, resp_chk(b1, b2, b3));
                    $finish;
               end

               $display("TB: PASS - WRITE8 0x%02X data=0x%02X => resp_data=0x%02X (STATUS=0x%02X)", waddr, wdata, b3, b1);

               #(BIT_PS * 3);
          end
     endtask

     initial
     begin
          $dumpfile("dump.vcd");
          $dumpvars(0, tb_ll5k_uart);

          uart_rx = 1'b1;

          $display("TB: Waiting for DUT internal POR release (dut.rst_i -> 0)...");
          wait (dut.rst_i == 1'b0);
          $display("TB: POR released at t=%0t", $time);

          #(BIT_PS * 5);

          // ID + VERSION
          do_read8_check(ID_ADDR,  8'h00, ID_VALUE);
          do_read8_check(VER_ADDR, 8'h00, VER_VALUE);

          // CONTROL defaults to 0
          do_read8_check(CONTROL_ADDR, 8'h00, 8'h00);

          // PZT_CLAMP_START_TIME defaults to 0x01
          do_read8_check(PZT_CLAMP_START_ADDR, 8'h00, PZT_CLAMP_START_DFLT);

          // Write/readback PZT_CLAMP_START_TIME
          do_write8_check(PZT_CLAMP_START_ADDR, 8'hA5, 8'h00, 8'hA5);
          do_read8_check (PZT_CLAMP_START_ADDR, 8'h00, 8'hA5);


          // Set TXD=1 (0x80) allowed when idle
          do_write8_check(CONTROL_ADDR, 8'h80, 8'h00, 8'h80);
          do_read8_check (CONTROL_ADDR, 8'h00, 8'h80);

          // Attempt set RXD=1 while TXD=1 => illegal, expect STATUS=0x02 and unchanged data
          do_write8_check(CONTROL_ADDR, 8'h40, 8'h02, 8'h80);
          do_read8_check (CONTROL_ADDR, 8'h00, 8'h80);

          // STATUS: ERR should be set after illegal operation, and clear-on-read
          do_read8_check (STATUS_ADDR,  8'h00, 8'h40);
          do_read8_check (STATUS_ADDR,  8'h00, 8'h00);

          // Attempt set PZT_GO=1 while TXD=1 => illegal under Policy 1
          do_write8_check(CONTROL_ADDR, 8'h02, 8'h02, 8'h80);

          // STATUS: ERR should be set again and clear-on-read
          do_read8_check (STATUS_ADDR,  8'h00, 8'h40);
          do_read8_check (STATUS_ADDR,  8'h00, 8'h00);

          // Clear CONTROL then set PZT_GO legally; STATUS mirrors CONTROL bit1
          do_write8_check(CONTROL_ADDR, 8'h00, 8'h00, 8'h00);
          do_write8_check(CONTROL_ADDR, 8'h02, 8'h00, 8'h02);
          do_read8_check (STATUS_ADDR,  8'h00, 8'h02);
          do_write8_check(CONTROL_ADDR, 8'h00, 8'h00, 8'h00);


          // Clear all
          do_write8_check(CONTROL_ADDR, 8'h00, 8'h00, 8'h00);
          do_read8_check (CONTROL_ADDR, 8'h00, 8'h00);

          // Trigger POR (self-clearing). Response data is 0x00 and then CONTROL reads 0x00.
          do_write8_check(CONTROL_ADDR, 8'h01, 8'h00, 8'h00);
          #(BIT_PS * 10);
          do_read8_check (CONTROL_ADDR, 8'h00, 8'h00);

          // After POR, PZT_CLAMP_START_TIME should return to default
          do_read8_check (PZT_CLAMP_START_ADDR, 8'h00, PZT_CLAMP_START_DFLT);

          $display("TB: ALL PASS");
          #(BIT_PS * 10);
          $finish;
     end

endmodule
