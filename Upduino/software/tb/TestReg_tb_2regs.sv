// ------------------------------------------------------------
// Testbench: ll5k UART pin-level verification (9600 8N1)
// Formatting: Whitesmiths braces + 5-space indent
// Notes:
//  - Integer picosecond delays only (Icarus-friendly).
//  - Correct 12 MHz clock: half-period = 41_667 ps (~41.667 ns).
//  - Waits for internal POR: dut.rst_i deassert.
//  - Adds timeout waiting for response start bit.
// ------------------------------------------------------------
`timescale 1ps/1ps

module tb_ll5k_uart
     ;

     localparam integer CLK_HZ = 12_000_000;
     localparam integer BAUD   = 9_600;

     // 12 MHz: half-period = 41.666... ns = 41_666.666... ps
     localparam longint CLK_HALF_PS = 41_667;

     // UART bit time = 1/9600 s = 104.166666... us = 104_166_666.666... ps
     localparam longint BIT_PS = 104_166_667;

     // Timeout waiting for DUT start bit on uart_tx
     localparam longint RESP_START_TIMEOUT_PS = (BIT_PS * 80);

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

     // 12 MHz clock
     initial
     begin
          clk = 1'b0;
          forever
          begin
               #(CLK_HALF_PS) clk = ~clk;
          end
     end

     // Host -> DUT byte TX (standard UART: LSB-first)
     task automatic uart_host_send_byte(input [7:0] b);
          integer i;
          begin
               uart_rx = 1'b0;          // start bit
               #(BIT_PS);

               for (i = 0; i < 8; i = i + 1)
               begin
                    uart_rx = b[i];     // LSB first
                    #(BIT_PS);
               end

               uart_rx = 1'b1;          // stop bit
               #(BIT_PS);
          end
     endtask

     // DUT -> Host byte RX (standard UART: LSB-first) + timeout
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

               #(BIT_PS + (BIT_PS / 2));     // mid-bit of bit0

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

     reg [7:0] b0, b1, b2, b3, b4;
     reg [7:0] op, addr, data, chk;

     initial
     begin
          $dumpfile("dump.vcd");
          $dumpvars(0, tb_ll5k_uart);

          uart_rx = 1'b1;

          $display("TB: Waiting for DUT internal POR release (dut.rst_i -> 0)...");
          wait (dut.rst_i == 1'b0);
          $display("TB: POR released at t=%0t", $time);

          #(BIT_PS * 5);

          // READ8 @ 0x00
          op   = 8'h01;
          addr = 8'h00;
          data = 8'h00;
          chk  = req_chk(op, addr, data);

          $display("TB: Sending READ8 request addr=0x%02X chk=0x%02X", addr, chk);

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

          if (b4 !== resp_chk(b1, b2, b3))
          begin
               $display("TB: FAIL - CHK mismatch got 0x%02X expected 0x%02X", b4, resp_chk(b1, b2, b3));
               $finish;
          end

          $display("TB: PASS - checksum OK. STATUS=0x%02X ADDR=0x%02X DATA=0x%02X", b1, b2, b3);

          #(BIT_PS * 10);
          $finish;
     end

endmodule
