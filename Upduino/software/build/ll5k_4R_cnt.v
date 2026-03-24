// ------------------------------------------------------------
// UPduino / iCE40UP5K - UART register block + CLK_DIV debug (v4)
// ------------------------------------------------------------
// Formatting note: Whitesmiths style (opening brace on new line) with 5-space indent.
//
// Top-level port names match the user's PCF:
//      input  clk
//      output clk_tst
//      input  uart_rx
//      output uart_tx
//
// UART protocol:
//      Request : 55 OP ADDR DATA CHK
//      Response: 56 STATUS ADDR DATA CHK
//      CHK = XOR of first 4 bytes
//
// Register summary (8-bit address map):
//      0x00 DEV_ID          (R/O) reset 0x01
//      0x01 ID              (R/O) reset 0x01
//      0x20 CLK_DIVISOR     (R/W) reset 0x0C     (N=0 treated as 1)
//      0x30 TEST            (R/W) reset 0x00     <-- UPDATED DEFAULT
//
// v4 change:
//      - TEST register (0x30) reset value changed from 0x5A to 0x00
// ------------------------------------------------------------

`timescale 1ns/1ps

module ll5k
     #(
          parameter integer CLK_HZ = 12_000_000,
          parameter integer BAUD   = 9_600
     )
     (
          input  wire clk,
          input  wire uart_rx,
          output reg  uart_tx,
          output reg  clk_tst
     );

     localparam [7:0] SOF_REQ  = 8'h55;
     localparam [7:0] SOF_RESP = 8'h56;

     localparam [7:0] OP_READ8  = 8'h01;
     localparam [7:0] OP_WRITE8 = 8'h02;

     localparam [7:0] REG_DEV_ID = 8'h00;
     localparam [7:0] REG_ID     = 8'h01;
     localparam [7:0] REG_CLKDIV = 8'h20;
     localparam [7:0] REG_TEST   = 8'h30;

     localparam [7:0] DEV_ID_RESET = 8'h01;
     localparam [7:0] ID_RESET     = 8'h01;
     localparam [7:0] CLKDIV_RESET = 8'h0C;
     localparam [7:0] TEST_RESET   = 8'h00;   // UPDATED

     localparam integer BAUD_DIV = (CLK_HZ / BAUD);

     reg [15:0] por_ctr;
     reg        por_n;

     initial
     begin
          por_ctr = 16'd0;
          por_n   = 1'b0;
          uart_tx = 1'b1;
          clk_tst = 1'b0;
     end

     always @(posedge clk)
     begin
          if (por_n == 1'b0)
          begin
               por_ctr <= por_ctr + 16'd1;
               if (por_ctr == 16'hFFFF)
               begin
                    por_n <= 1'b1;
               end
          end
     end

     // UART RX (unchanged)
     reg [10:0] rx_clk_ctr;
     reg [3:0]  rx_bit_ctr;
     reg [2:0]  rx_byte_ctr;
     reg [7:0]  rx_shift;
     reg        rx_busy;

     reg [7:0]  req_op;
     reg [7:0]  req_addr;
     reg [7:0]  req_data;
     reg [7:0]  req_chk;
     reg        req_valid;

     always @(posedge clk)
     begin
          if (por_n == 1'b0)
          begin
               rx_clk_ctr  <= 11'd0;
               rx_bit_ctr  <= 4'd0;
               rx_byte_ctr <= 3'd0;
               rx_shift    <= 8'd0;
               rx_busy     <= 1'b0;
               req_op      <= 8'd0;
               req_addr    <= 8'd0;
               req_data    <= 8'd0;
               req_chk     <= 8'd0;
               req_valid   <= 1'b0;
          end
          else
          begin
               req_valid <= 1'b0;
               if (rx_busy == 1'b0)
               begin
                    if (uart_rx == 1'b0)
                    begin
                         rx_busy    <= 1'b1;
                         rx_clk_ctr <= 11'd0;
                         rx_bit_ctr <= 4'd0;
                         rx_shift   <= 8'd0;
                    end
               end
               else
               begin
                    rx_clk_ctr <= rx_clk_ctr + 11'd1;
                    if (rx_bit_ctr == 4'd0)
                    begin
                         if (rx_clk_ctr == (BAUD_DIV / 2))
                         begin
                              if (uart_rx != 1'b0)
                              begin
                                   rx_busy <= 1'b0;
                              end
                              rx_clk_ctr <= 11'd0;
                              rx_bit_ctr <= 4'd1;
                         end
                    end
                    else if ((rx_bit_ctr >= 4'd1) && (rx_bit_ctr <= 4'd8))
                    begin
                         if (rx_clk_ctr == (BAUD_DIV - 1))
                         begin
                              rx_shift   <= { uart_rx, rx_shift[7:1] };
                              rx_clk_ctr <= 11'd0;
                              rx_bit_ctr <= rx_bit_ctr + 4'd1;
                         end
                    end
                    else if (rx_bit_ctr == 4'd9)
                    begin
                         if (rx_clk_ctr == (BAUD_DIV - 1))
                         begin
                              rx_busy    <= 1'b0;
                              rx_clk_ctr <= 11'd0;
                              rx_bit_ctr <= 4'd0;
                              if (uart_rx == 1'b1)
                              begin
                                   if (rx_byte_ctr == 3'd0)
                                   begin
                                        if (rx_shift == SOF_REQ)
                                             rx_byte_ctr <= 3'd1;
                                        else
                                             rx_byte_ctr <= 3'd0;
                                   end
                                   else if (rx_byte_ctr == 3'd1)
                                   begin
                                        req_op      <= rx_shift;
                                        rx_byte_ctr <= 3'd2;
                                   end
                                   else if (rx_byte_ctr == 3'd2)
                                   begin
                                        req_addr    <= rx_shift;
                                        rx_byte_ctr <= 3'd3;
                                   end
                                   else if (rx_byte_ctr == 3'd3)
                                   begin
                                        req_data    <= rx_shift;
                                        rx_byte_ctr <= 3'd4;
                                   end
                                   else
                                   begin
                                        req_chk     <= rx_shift;
                                        rx_byte_ctr <= 3'd0;
                                        req_valid   <= 1'b1;
                                   end
                              end
                              else
                                   rx_byte_ctr <= 3'd0;
                         end
                    end
               end
          end
     end

     wire [7:0] req_chk_calc = SOF_REQ ^ req_op ^ req_addr ^ req_data;
     wire       req_chk_ok   = (req_chk_calc == req_chk);

     // Register file
     reg [7:0] reg_clkdiv;
     reg [7:0] reg_test;

     always @(posedge clk)
     begin
          if (por_n == 1'b0)
          begin
               reg_clkdiv <= CLKDIV_RESET;
               reg_test   <= TEST_RESET;
          end
          else if ((req_valid == 1'b1) && (req_chk_ok == 1'b1) && (req_op == OP_WRITE8))
          begin
               if (req_addr == REG_CLKDIV)
                    reg_clkdiv <= req_data;
               else if (req_addr == REG_TEST)
                    reg_test <= req_data;
          end
     end

     function [7:0] reg_read;
          input [7:0] addr;
          begin
               case (addr)
                    REG_DEV_ID: reg_read = DEV_ID_RESET;
                    REG_ID:     reg_read = ID_RESET;
                    REG_CLKDIV: reg_read = reg_clkdiv;
                    REG_TEST:   reg_read = reg_test;
                    default:    reg_read = 8'h00;
               endcase
          end
     endfunction

     // Divider
     reg [7:0] div_cnt;
     wire [7:0] div_n_raw = reg_clkdiv;
     wire [7:0] div_n     = (div_n_raw == 8'd0) ? 8'd1 : div_n_raw;
     wire [7:0] div_half  = ((div_n >> 1) == 8'd0) ? 8'd1 : (div_n >> 1);

     always @(posedge clk)
     begin
          if (por_n == 1'b0)
          begin
               div_cnt <= 8'd0;
               clk_tst <= 1'b0;
          end
          else
          begin
               if (div_cnt == (div_n - 8'd1))
               begin
                    div_cnt <= 8'd0;
                    clk_tst <= ~clk_tst;
               end
               else if (div_cnt == (div_half - 8'd1))
               begin
                    div_cnt <= div_cnt + 8'd1;
                    clk_tst <= ~clk_tst;
               end
               else
                    div_cnt <= div_cnt + 8'd1;
          end
     end

     // UART TX (unchanged)
     reg [10:0] tx_clk_ctr;
     reg [3:0]  tx_bit_ctr;
     reg [2:0]  tx_byte_ctr;
     reg [7:0]  tx_shift;
     reg        tx_busy;

     reg [7:0]  resp_status;
     reg [7:0]  resp_addr;
     reg [7:0]  resp_data;

     wire [7:0] resp_chk = SOF_RESP ^ resp_status ^ resp_addr ^ resp_data;

     always @(posedge clk)
     begin
          if (por_n == 1'b0)
          begin
               tx_clk_ctr  <= 11'd0;
               tx_bit_ctr  <= 4'd0;
               tx_byte_ctr <= 3'd0;
               tx_shift    <= 8'd0;
               tx_busy     <= 1'b0;
               resp_status <= 8'h00;
               resp_addr   <= 8'h00;
               resp_data   <= 8'h00;
               uart_tx     <= 1'b1;
          end
          else
          begin
               if ((req_valid == 1'b1) && (tx_busy == 1'b0) && (req_chk_ok == 1'b1))
               begin
                    resp_status <= 8'h00;
                    resp_addr   <= req_addr;
                    if (req_op == OP_READ8)
                         resp_data <= reg_read(req_addr);
                    else if (req_op == OP_WRITE8)
                         resp_data <= req_data;
                    else
                    begin
                         resp_status <= 8'h01;
                         resp_data   <= 8'h00;
                    end
                    tx_busy     <= 1'b1;
                    tx_byte_ctr <= 3'd0;
                    tx_bit_ctr  <= 4'd0;
                    tx_clk_ctr  <= 11'd0;
               end

               if (tx_busy == 1'b1)
               begin
                    tx_clk_ctr <= tx_clk_ctr + 11'd1;
                    if (tx_bit_ctr == 4'd0)
                    begin
                         case (tx_byte_ctr)
                              3'd0: tx_shift <= SOF_RESP;
                              3'd1: tx_shift <= resp_status;
                              3'd2: tx_shift <= resp_addr;
                              3'd3: tx_shift <= resp_data;
                              default: tx_shift <= resp_chk;
                         endcase
                         uart_tx    <= 1'b0;
                         tx_bit_ctr <= 4'd1;
                         tx_clk_ctr <= 11'd0;
                    end
                    else if ((tx_bit_ctr >= 4'd1) && (tx_bit_ctr <= 4'd8))
                    begin
                         if (tx_clk_ctr == (BAUD_DIV - 1))
                         begin
                              uart_tx    <= tx_shift[0];
                              tx_shift   <= { 1'b0, tx_shift[7:1] };
                              tx_bit_ctr <= tx_bit_ctr + 4'd1;
                              tx_clk_ctr <= 11'd0;
                         end
                    end
                    else if (tx_bit_ctr == 4'd9)
                    begin
                         if (tx_clk_ctr == (BAUD_DIV - 1))
                         begin
                              uart_tx    <= 1'b1;
                              tx_bit_ctr <= 4'd10;
                              tx_clk_ctr <= 11'd0;
                         end
                    end
                    else if (tx_clk_ctr == (BAUD_DIV - 1))
                    begin
                         tx_clk_ctr <= 11'd0;
                         tx_bit_ctr <= 4'd0;
                         if (tx_byte_ctr == 3'd4)
                         begin
                              tx_busy     <= 1'b0;
                              tx_byte_ctr <= 3'd0;
                         end
                         else
                              tx_byte_ctr <= tx_byte_ctr + 3'd1;
                    end
               end
          end
     end

endmodule
