// -----------------------------------------------------------------------------
// LL5k_WIP.v
// -----------------------------------------------------------------------------
// UPduino / iCE40UP5K UART register file (Work-In-Progress baseline)
// Protocol:
//   Request : 0x55 OP ADDR DATA CHK
//   Response: 0x56 STATUS ADDR DATA CHK
//   CHK = XOR of first 4 bytes (SYNC/STATUS/ADDR/DATA) for the frame.
//
// Notes:
//   - Single-file RTL (no external module dependencies)
//   - Deterministic internal power-on reset (POR)
//   - External IO polarity is TRUE (idle-high UART, active-high semantics)
//   - Whitesmiths formatting, 5-space indent
//
// Implemented registers (8-bit address space):
//   0x00 ID                           (R/O) = 0x01
//   0x01 VERSION                      (R/O) = 0x01
//   0x21 PZT_CLAMP_START_TIME          (R/W) reset 0x01
//   0x22 PZT_CLAMP_STOP_TIME           (R/W) reset 0x02
//   0x23 RECEIVE_WINDOW_START_TIME     (R/W) reset 0x03
//        Failsafe clamp: RX_START >= PZT_CLAMP_STOP_TIME + 1 (saturating add)
//   0x24 RECEIVE_WINDOW_STOP_TIME      (R/W) reset 0x04
//        Failsafe clamp: RX_STOP  >= RX_START + 1 (saturating add)
//   0x30 TEST_REG                      (R/W) reset 0x00
//
// Status byte (response):
//   bit0: ERR (0=OK, 1=error)
//   bit1: RX_START_CLAMPED (1 if RX_START was clamped on last relevant write)
//   bit2: RX_STOP_CLAMPED  (1 if RX_STOP  was clamped on last relevant write)
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module LL5k_WIP
     #(
          parameter integer CLK_HZ = 12_000_000,
          parameter integer BAUD   = 9_600
     )
     (
          input  wire        clk,
          input  wire        uart_rx,
          output reg         uart_tx
     );

     // ------------------------------------------------------------------------
     // Register summary (instantiated state elements)
     // ------------------------------------------------------------------------
     //  - por_cnt                      : power-on reset counter
     //  - por_n                        : internal reset released after POR
     //
     //  - reg_pzt_clamp_start_time     : 0x21 R/W
     //  - reg_pzt_clamp_stop_time      : 0x22 R/W
     //  - reg_rx_window_start_time     : 0x23 R/W (clamped vs PZT_STOP+1)
     //  - reg_rx_window_stop_time      : 0x24 R/W (clamped vs RX_START+1)
     //  - reg_test                     : 0x30 R/W
     //
     //  - status_rx_start_clamped      : status bit1
     //  - status_rx_stop_clamped       : status bit2
     //
     //  - UART RX state regs           : rx_state, rx_shift, rx_bit_cnt, rx_tick_cnt, rx_byte, rx_byte_valid
     //  - UART TX state regs           : tx_state, tx_shift, tx_bit_cnt, tx_tick_cnt
     //  - Frame regs                   : f_op, f_addr, f_data, f_chk, f_count
     //  - Response regs                : resp_status, resp_addr, resp_data, resp_idx, resp_pending
     // ------------------------------------------------------------------------

     // ------------------------------------------------------------------------
     // Internal POR (deterministic reset after configuration)
     // ------------------------------------------------------------------------
     localparam integer POR_CYCLES = (CLK_HZ / 1000);  // ~1ms
     reg [31:0] por_cnt;
     reg        por_n;

     always @(posedge clk)
     begin
          if (!por_n)
          begin
               if (por_cnt >= (POR_CYCLES - 1))
               begin
                    por_n   <= 1'b1;
                    por_cnt <= por_cnt;
               end
               else
               begin
                    por_cnt <= por_cnt + 32'd1;
               end
          end
     end

     initial
     begin
          por_cnt = 32'd0;
          por_n   = 1'b0;
     end

     // ------------------------------------------------------------------------
     // UART timing (simple integer divider)
     // ------------------------------------------------------------------------
     localparam integer BAUD_DIV = (CLK_HZ / BAUD);   // 12e6/9600=1250

     // ------------------------------------------------------------------------
     // UART RX: 8N1, LSB first
     // ------------------------------------------------------------------------
     localparam integer RX_IDLE  = 0;
     localparam integer RX_START = 1;
     localparam integer RX_DATA  = 2;
     localparam integer RX_STOP  = 3;

     reg [1:0]  rx_state;
     reg [15:0] rx_tick_cnt;
     reg [2:0]  rx_bit_cnt;
     reg [7:0]  rx_shift;
     reg [7:0]  rx_byte;
     reg        rx_byte_valid;

     always @(posedge clk)
     begin
          if (!por_n)
          begin
               rx_state      <= RX_IDLE;
               rx_tick_cnt   <= 16'd0;
               rx_bit_cnt    <= 3'd0;
               rx_shift      <= 8'd0;
               rx_byte       <= 8'd0;
               rx_byte_valid <= 1'b0;
          end
          else
          begin
               rx_byte_valid <= 1'b0;

               case (rx_state)
               RX_IDLE:
               begin
                    rx_tick_cnt <= 16'd0;
                    rx_bit_cnt  <= 3'd0;
                    if (uart_rx == 1'b0)
                    begin
                         rx_state    <= RX_START;
                         rx_tick_cnt <= 16'd0;
                    end
               end

               RX_START:
               begin
                    if (rx_tick_cnt == (BAUD_DIV/2))
                    begin
                         if (uart_rx == 1'b0)
                         begin
                              rx_state    <= RX_DATA;
                              rx_tick_cnt <= 16'd0;
                              rx_bit_cnt  <= 3'd0;
                         end
                         else
                         begin
                              rx_state <= RX_IDLE;
                         end
                    end
                    else
                    begin
                         rx_tick_cnt <= rx_tick_cnt + 16'd1;
                    end
               end

               RX_DATA:
               begin
                    if (rx_tick_cnt == (BAUD_DIV-1))
                    begin
                         rx_tick_cnt <= 16'd0;
                         rx_shift    <= { uart_rx, rx_shift[7:1] };

                         if (rx_bit_cnt == 3'd7)
                         begin
                              rx_state   <= RX_STOP;
                              rx_bit_cnt <= 3'd0;
                         end
                         else
                         begin
                              rx_bit_cnt <= rx_bit_cnt + 3'd1;
                         end
                    end
                    else
                    begin
                         rx_tick_cnt <= rx_tick_cnt + 16'd1;
                    end
               end

               RX_STOP:
               begin
                    if (rx_tick_cnt == (BAUD_DIV-1))
                    begin
                         rx_tick_cnt <= 16'd0;
                         if (uart_rx == 1'b1)
                         begin
                              rx_byte       <= rx_shift;
                              rx_byte_valid <= 1'b1;
                         end
                         rx_state <= RX_IDLE;
                    end
                    else
                    begin
                         rx_tick_cnt <= rx_tick_cnt + 16'd1;
                    end
               end

               default:
               begin
                    rx_state <= RX_IDLE;
               end
               endcase
          end
     end

     // ------------------------------------------------------------------------
     // UART TX: 8N1, LSB first
     // ------------------------------------------------------------------------
     localparam integer TX_IDLE  = 0;
     localparam integer TX_START = 1;
     localparam integer TX_DATA  = 2;
     localparam integer TX_STOP  = 3;

     reg [1:0]  tx_state;
     reg [15:0] tx_tick_cnt;
     reg [2:0]  tx_bit_cnt;
     reg [7:0]  tx_shift;
     reg        tx_busy;

     task automatic tx_start_byte;
          input [7:0] b;
          begin
               tx_state    <= TX_START;
               tx_tick_cnt <= 16'd0;
               tx_bit_cnt  <= 3'd0;
               tx_shift    <= b;
               tx_busy     <= 1'b1;
          end
     endtask

     always @(posedge clk)
     begin
          if (!por_n)
          begin
               uart_tx     <= 1'b1;
               tx_state    <= TX_IDLE;
               tx_tick_cnt <= 16'd0;
               tx_bit_cnt  <= 3'd0;
               tx_shift    <= 8'd0;
               tx_busy     <= 1'b0;
          end
          else
          begin
               case (tx_state)
               TX_IDLE:
               begin
                    uart_tx <= 1'b1;
                    tx_busy <= 1'b0;
               end

               TX_START:
               begin
                    uart_tx <= 1'b0;
                    if (tx_tick_cnt == (BAUD_DIV-1))
                    begin
                         tx_tick_cnt <= 16'd0;
                         tx_state    <= TX_DATA;
                    end
                    else
                    begin
                         tx_tick_cnt <= tx_tick_cnt + 16'd1;
                    end
               end

               TX_DATA:
               begin
                    uart_tx <= tx_shift[0];
                    if (tx_tick_cnt == (BAUD_DIV-1))
                    begin
                         tx_tick_cnt <= 16'd0;
                         tx_shift    <= { 1'b0, tx_shift[7:1] };

                         if (tx_bit_cnt == 3'd7)
                         begin
                              tx_bit_cnt <= 3'd0;
                              tx_state   <= TX_STOP;
                         end
                         else
                         begin
                              tx_bit_cnt <= tx_bit_cnt + 3'd1;
                         end
                    end
                    else
                    begin
                         tx_tick_cnt <= tx_tick_cnt + 16'd1;
                    end
               end

               TX_STOP:
               begin
                    uart_tx <= 1'b1;
                    if (tx_tick_cnt == (BAUD_DIV-1))
                    begin
                         tx_tick_cnt <= 16'd0;
                         tx_state    <= TX_IDLE;
                    end
                    else
                    begin
                         tx_tick_cnt <= tx_tick_cnt + 16'd1;
                    end
               end

               default:
               begin
                    tx_state <= TX_IDLE;
               end
               endcase
          end
     end

     // ------------------------------------------------------------------------
     // Register bank
     // ------------------------------------------------------------------------
     reg [7:0] reg_pzt_clamp_start_time;   // 0x21
     reg [7:0] reg_pzt_clamp_stop_time;    // 0x22
     reg [7:0] reg_rx_window_start_time;   // 0x23
     reg [7:0] reg_rx_window_stop_time;    // 0x24
     reg [7:0] reg_test;                   // 0x30

     // Constants
     wire [7:0] reg_id  = 8'h01;
     wire [7:0] reg_ver = 8'h01;

     // Helpers (saturating +1)
     function automatic [7:0] sat_plus_1;
          input [7:0] v;
          begin
               if (v == 8'hFF)
               begin
                    sat_plus_1 = 8'hFF;
               end
               else
               begin
                    sat_plus_1 = v + 8'h01;
               end
          end
     endfunction

     // ------------------------------------------------------------------------
     // Frame receive / response generation
     // ------------------------------------------------------------------------
     localparam [7:0] SYNC_REQ  = 8'h55;
     localparam [7:0] SYNC_RESP = 8'h56;

     localparam [7:0] OP_READ8  = 8'h01;
     localparam [7:0] OP_WRITE8 = 8'h02;

     // Status bits
     reg status_rx_start_clamped;   // bit1
     reg status_rx_stop_clamped;    // bit2

     // Frame assembly
     reg [7:0] f_op;
     reg [7:0] f_addr;
     reg [7:0] f_data;
     reg [7:0] f_chk;
     reg [2:0] f_count;
     reg       frame_ready;

     // Response queue
     reg [7:0] resp_status;
     reg [7:0] resp_addr;
     reg [7:0] resp_data;
     reg [2:0] resp_idx;
     reg       resp_pending;

     function automatic [7:0] calc_chk4;
          input [7:0] b0;
          input [7:0] b1;
          input [7:0] b2;
          input [7:0] b3;
          begin
               calc_chk4 = b0 ^ b1 ^ b2 ^ b3;
          end
     endfunction

     function automatic [7:0] reg_read;
          input [7:0] a;
          begin
               case (a)
               8'h00: reg_read = reg_id;
               8'h01: reg_read = reg_ver;
               8'h21: reg_read = reg_pzt_clamp_start_time;
               8'h22: reg_read = reg_pzt_clamp_stop_time;
               8'h23: reg_read = reg_rx_window_start_time;
               8'h24: reg_read = reg_rx_window_stop_time;
               8'h30: reg_read = reg_test;
               default: reg_read = 8'h00;
               endcase
          end
     endfunction

     initial
     begin
          reg_pzt_clamp_start_time  = 8'h01;
          reg_pzt_clamp_stop_time   = 8'h02;
          reg_rx_window_start_time  = 8'h03;
          reg_rx_window_stop_time   = 8'h04;  // failsafe: STOP > START
          reg_test                  = 8'h00;

          status_rx_start_clamped   = 1'b0;
          status_rx_stop_clamped    = 1'b0;

          f_op                      = 8'h00;
          f_addr                    = 8'h00;
          f_data                    = 8'h00;
          f_chk                     = 8'h00;
          f_count                   = 3'd0;
          frame_ready               = 1'b0;

          resp_status               = 8'h00;
          resp_addr                 = 8'h00;
          resp_data                 = 8'h00;
          resp_idx                  = 3'd0;
          resp_pending              = 1'b0;
     end

     always @(posedge clk)
     begin
          if (!por_n)
          begin
               f_count                 <= 3'd0;
               frame_ready             <= 1'b0;
               resp_pending            <= 1'b0;
               resp_idx                <= 3'd0;
               resp_status             <= 8'h00;
               resp_addr               <= 8'h00;
               resp_data               <= 8'h00;

               status_rx_start_clamped <= 1'b0;
               status_rx_stop_clamped  <= 1'b0;

               reg_pzt_clamp_start_time <= 8'h01;
               reg_pzt_clamp_stop_time  <= 8'h02;
               reg_rx_window_start_time <= 8'h03;
               reg_rx_window_stop_time  <= 8'h04;
               reg_test                 <= 8'h00;
          end
          else
          begin
               frame_ready <= 1'b0;

               // Accumulate request bytes
               if (rx_byte_valid)
               begin
                    if (f_count == 3'd0)
                    begin
                         if (rx_byte == SYNC_REQ)
                         begin
                              f_count <= 3'd1;
                         end
                         else
                         begin
                              f_count <= 3'd0;
                         end
                    end
                    else if (f_count == 3'd1)
                    begin
                         f_op    <= rx_byte;
                         f_count <= 3'd2;
                    end
                    else if (f_count == 3'd2)
                    begin
                         f_addr  <= rx_byte;
                         f_count <= 3'd3;
                    end
                    else if (f_count == 3'd3)
                    begin
                         f_data  <= rx_byte;
                         f_count <= 3'd4;
                    end
                    else
                    begin
                         f_chk       <= rx_byte;
                         f_count     <= 3'd0;
                         frame_ready <= 1'b1;
                    end
               end

               // Build response when frame is ready and TX idle
               if (frame_ready && !resp_pending && (tx_state == TX_IDLE))
               begin
                    reg [7:0] err_bit;
                    reg [7:0] new_rx_start;
                    reg [7:0] new_rx_stop;
                    reg [7:0] pzt_stop_plus_1;
                    reg [7:0] rx_start_plus_1;

                    err_bit          = 8'h00;
                    resp_addr        <= f_addr;
                    resp_data        <= 8'h00;
                    resp_status      <= 8'h00;

                    // Default: retain current values
                    new_rx_start     = reg_rx_window_start_time;
                    new_rx_stop      = reg_rx_window_stop_time;

                    // Precompute constraints
                    pzt_stop_plus_1  = sat_plus_1(reg_pzt_clamp_stop_time);
                    rx_start_plus_1  = sat_plus_1(new_rx_start);

                    if (f_chk != calc_chk4(SYNC_REQ, f_op, f_addr, f_data))
                    begin
                         err_bit = 8'h01;
                    end
                    else
                    begin
                         if (f_op == OP_READ8)
                         begin
                              resp_data <= reg_read(f_addr);
                         end
                         else if (f_op == OP_WRITE8)
                         begin
                              // Clear per-transaction clamp indicators; they will be reasserted if needed.
                              status_rx_start_clamped <= 1'b0;
                              status_rx_stop_clamped  <= 1'b0;

                              if (f_addr == 8'h21)
                              begin
                                   reg_pzt_clamp_start_time <= f_data;
                              end
                              else if (f_addr == 8'h22)
                              begin
                                   reg_pzt_clamp_stop_time <= f_data;

                                   // If STOP moves forward, RX_START must be >= STOP+1
                                   pzt_stop_plus_1 = sat_plus_1(f_data);
                                   if (reg_rx_window_start_time < pzt_stop_plus_1)
                                   begin
                                        new_rx_start            = pzt_stop_plus_1;
                                        status_rx_start_clamped <= 1'b1;
                                   end

                                   // After adjusting RX_START, RX_STOP must be >= RX_START+1
                                   rx_start_plus_1 = sat_plus_1(new_rx_start);
                                   if (reg_rx_window_stop_time < rx_start_plus_1)
                                   begin
                                        new_rx_stop            = rx_start_plus_1;
                                        status_rx_stop_clamped <= 1'b1;
                                   end
                              end
                              else if (f_addr == 8'h23)
                              begin
                                   // Clamp RX_START vs PZT_STOP+1
                                   pzt_stop_plus_1 = sat_plus_1(reg_pzt_clamp_stop_time);
                                   if (f_data < pzt_stop_plus_1)
                                   begin
                                        new_rx_start            = pzt_stop_plus_1;
                                        status_rx_start_clamped <= 1'b1;
                                   end
                                   else
                                   begin
                                        new_rx_start = f_data;
                                   end

                                   // Clamp RX_STOP vs RX_START+1
                                   rx_start_plus_1 = sat_plus_1(new_rx_start);
                                   if (reg_rx_window_stop_time < rx_start_plus_1)
                                   begin
                                        new_rx_stop            = rx_start_plus_1;
                                        status_rx_stop_clamped <= 1'b1;
                                   end
                              end
                              else if (f_addr == 8'h24)
                              begin
                                   // Clamp RX_STOP vs RX_START+1
                                   rx_start_plus_1 = sat_plus_1(reg_rx_window_start_time);
                                   if (f_data < rx_start_plus_1)
                                   begin
                                        new_rx_stop            = rx_start_plus_1;
                                        status_rx_stop_clamped <= 1'b1;
                                   end
                                   else
                                   begin
                                        new_rx_stop = f_data;
                                   end
                              end
                              else if (f_addr == 8'h30)
                              begin
                                   reg_test <= f_data;
                              end

                              // Commit any derived updates
                              reg_rx_window_start_time <= new_rx_start;
                              reg_rx_window_stop_time  <= new_rx_stop;

                              resp_data <= reg_read(f_addr);
                         end
                         else
                         begin
                              err_bit = 8'h01;
                         end
                    end

                    // Compose status: [7:3]=0, bit2 stop_clamped, bit1 start_clamped, bit0 err
                    resp_status  <= { 5'b0, status_rx_stop_clamped, status_rx_start_clamped, err_bit[0] };

                    resp_pending <= 1'b1;
                    resp_idx     <= 3'd0;
               end

               // Send response bytes (SYNC, STATUS, ADDR, DATA, CHK)
               if (resp_pending && (tx_state == TX_IDLE))
               begin
                    if (resp_idx == 3'd0)
                    begin
                         tx_start_byte(SYNC_RESP);
                         resp_idx <= 3'd1;
                    end
                    else if (resp_idx == 3'd1)
                    begin
                         tx_start_byte(resp_status);
                         resp_idx <= 3'd2;
                    end
                    else if (resp_idx == 3'd2)
                    begin
                         tx_start_byte(resp_addr);
                         resp_idx <= 3'd3;
                    end
                    else if (resp_idx == 3'd3)
                    begin
                         tx_start_byte(resp_data);
                         resp_idx <= 3'd4;
                    end
                    else
                    begin
                         tx_start_byte(calc_chk4(SYNC_RESP, resp_status, resp_addr, resp_data));
                         resp_idx     <= 3'd0;
                         resp_pending <= 1'b0;
                    end
               end
          end
     end

endmodule
