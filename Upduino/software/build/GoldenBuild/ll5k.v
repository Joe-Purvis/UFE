// ------------------------------------------------------------
// UPduino UART register test (Whitesmiths formatting, 5-space indent)
// File: ll5k.v
//
// Device clock  : 12 MHz
// UART          : 9600 8N1
//
// Protocol:
//   Request : 55 OP ADDR DATA CHK
//   Response: 56 STATUS ADDR DATA CHK
//
// Notes:
//   - Single-file design: one top-level module only (ll5k)
//   - Internal power-on reset generated in RTL
//   - 16x oversampling; corrected NCO tick16
//   - TX start is LATCHED (tx_req) so it cannot be missed
//   - TX byte loading is indexed explicitly (fixes off-by-one / wrong last byte)
//   - Minimal register map:
//        addr 0x30 = TEST register (reset value 0x5A)
// ------------------------------------------------------------

// ============================================================
// KNOWN-GOOD UART BASELINE (hardware-verified)
// Source: ll5k_testreg_top.v
//
// Verified behaviour (PC-side):
//   Request : 55 01 30 00 64
//   Response: 56 00 30 5A 3C
//
// Notes:
//   - Keep this file as a frozen reference.
//   - Make changes in ll5k_testreg_top.v only, with regression test.
// ============================================================

// ------------------------------------------------------------
// Tooling hygiene:
//   `default_nettype none forces explicit net declarations and
//   helps catch typos that would otherwise create implicit wires.
// ------------------------------------------------------------

`default_nettype none

module ll5k
     #(
          parameter integer CLK_HZ = 12_000_000,
          parameter integer BAUD   = 9_600
     )
     (
          input  wire clk,
          input  wire uart_rx,
          output wire uart_tx
     );

     // --------------------------------------------------------
     // Register inventory (instantiated storage elements)
     //
     //   por_cnt     : 20-bit power-on reset counter
     //   rst_i       : internal synchronous reset (asserted during POR)
     //   acc         : NCO accumulator for 16x baud tick generation
     //   tick16      : 1-clock pulse at 16x baud rate (when enabled)
     //   rx_*        : UART RX state (oversample phase, bit index, shift reg)
     //   test_reg    : 8-bit R/W register at address 0x30 (reset 0x5A)
     //   p_state/op/addr/data : protocol decode state and latched fields
     //   resp_*      : response frame fields (status/addr/data/chk)
     //   tx_*        : UART TX state (latched request, shifter, counters)
     //
     // Notes:
     //   - All state is synchronous to clk.
     //   - tick16 is the only timebase used for RX/TX bit timing.
     // --------------------------------------------------------


     // --------------------------------------------------------
     // Internal reset (power-on reset counter)
     // --------------------------------------------------------
     reg [19:0] por_cnt = 20'd0;
     reg        rst_i   = 1'b1;

     // POR implementation detail:
     //   - por_cnt increments from 0 to 0xFFFFF after configuration.
     //   - rst_i is held HIGH while por_cnt is counting.
     //   - When por_cnt saturates, rst_i deasserts LOW permanently.
     //
     // This avoids reliance on global reset pins and gives deterministic
     // startup for both the UART RX and TX state machines.

     always @(posedge clk)
     begin
          if (por_cnt != 20'hFFFFF)
          begin
               por_cnt <= por_cnt + 1'b1;
               rst_i   <= 1'b1;
          end
          else
          begin
               rst_i <= 1'b0;
          end
     end

     // --------------------------------------------------------
     // 16x baud tick generator using corrected NCO
     // --------------------------------------------------------
     localparam integer BAUD16 = BAUD * 16;

     reg  [32:0] acc    = 33'd0;
     reg         tick16 = 1'b0;

     wire [32:0] acc_next = acc + BAUD16;

     // NCO tick16 generation:
     //   We want a tick at BAUD*16. Because CLK_HZ / (BAUD*16) is not an
     //   integer in general, we use a phase-accumulator (NCO) method.
     //
     //   Each clock: acc_next = acc + BAUD16.
     //   If acc_next >= CLK_HZ, we wrap (subtract CLK_HZ) and assert tick16.
     //
     // This produces the correct *average* tick rate with bounded jitter of
     // at most +/- 1 clk period, which is acceptable for 16x oversampling.

     always @(posedge clk)
     begin
          if (rst_i)
          begin
               acc    <= 33'd0;
               tick16 <= 1'b0;
          end
          else
          begin
               if (acc_next >= CLK_HZ)
               begin
                    acc    <= acc_next - CLK_HZ;
                    tick16 <= 1'b1;
               end
               else
               begin
                    acc    <= acc_next;
                    tick16 <= 1'b0;
               end
          end
     end

     // --------------------------------------------------------
     // UART RX (16x oversampling, mid-bit sampling, stop-bit check)
     // Produces rx_valid (1 clk pulse) with rx_byte
     // --------------------------------------------------------
     reg        rx_busy  = 1'b0;
     reg [3:0]  rx_sub   = 4'd0;
     reg [3:0]  rx_bit   = 4'd0;
     reg [7:0]  rx_shift = 8'd0;
     reg [7:0]  rx_byte  = 8'd0;
     reg        rx_valid = 1'b0;

     // UART RX strategy (robust at low baud):
     //   - Wait for a falling edge (uart_rx == 0) to detect a start bit.
     //   - Use tick16 as the oversample strobe (16 samples per bit).
     //   - Sample at rx_sub == 7 (mid-bit) to minimise sensitivity to jitter.
     //   - Shift in 8 data bits LSB-first.
     //   - Validate stop bit (must be HIGH) before asserting rx_valid.
     //
     // Timing notes:
     //   rx_bit meanings at mid-bit sample (rx_sub==7):
     //     0 : start bit check
     //     1..8 : data bits (LSB first)
     //     9 : stop bit check
     //
     // Outputs:
     //   rx_valid pulses for 1 clk cycle when a full byte is received.
     //   rx_byte holds that received byte.

     always @(posedge clk)
     begin
          rx_valid <= 1'b0;

          if (rst_i)
          begin
               rx_busy  <= 1'b0;
               rx_sub   <= 4'd0;
               rx_bit   <= 4'd0;
               rx_shift <= 8'd0;
          end
          else if (tick16)
          begin
               if (!rx_busy)
               begin
                    if (uart_rx == 1'b0)
                    begin
                         rx_busy <= 1'b1;
                         rx_sub  <= 4'd0;
                         rx_bit  <= 4'd0;
                    end
               end
               else
               begin
                    rx_sub <= rx_sub + 1'b1;

                    if (rx_sub == 4'd7)
                    begin
                         if (rx_bit == 4'd0)
                         begin
                              if (uart_rx != 1'b0)
                              begin
                                   rx_busy <= 1'b0;
                              end
                         end
                         else if (rx_bit >= 4'd1 && rx_bit <= 4'd8)
                         begin
                              rx_shift <= { uart_rx, rx_shift[7:1] };
                         end
                         else if (rx_bit == 4'd9)
                         begin
                              if (uart_rx == 1'b1)
                              begin
                                   rx_byte  <= rx_shift;
                                   rx_valid <= 1'b1;
                              end
                              rx_busy <= 1'b0;
                         end
                    end

                    if (rx_sub == 4'd15)
                    begin
                         rx_bit <= rx_bit + 1'b1;

                         if (rx_bit == 4'd10)
                         begin
                              rx_busy <= 1'b0;
                         end
                    end
               end
          end
     end

     // --------------------------------------------------------
     // Minimal register map: TEST register at 0x30
     // --------------------------------------------------------
     localparam [7:0] TEST_ADDR = 8'h30;
     reg [7:0]        test_reg  = 8'h5A;

     // --------------------------------------------------------
     // Protocol state machine (RX parses 5 bytes)
     // --------------------------------------------------------
     localparam P_IDLE = 3'd0;
     localparam P_OP   = 3'd1;
     localparam P_ADDR = 3'd2;
     localparam P_DATA = 3'd3;
     localparam P_CHK  = 3'd4;

     reg [2:0] p_state = P_IDLE;
     reg [7:0] op      = 8'h00;
     reg [7:0] addr    = 8'h00;
     reg [7:0] data    = 8'h00;

     // Response fields
     reg [7:0] resp_status = 8'h00;
     reg [7:0] resp_addr   = 8'h00;
     reg [7:0] resp_data   = 8'h00;
     reg [7:0] resp_chk    = 8'h00;

     reg [7:0] status_n;
     reg [7:0] data_n;

     // --------------------------------------------------------
     // UART TX engine (latched start request tx_req)
     // --------------------------------------------------------
     reg        tx_req   = 1'b0;
     reg        tx_busy  = 1'b0;
     reg [2:0]  tx_index = 3'd0;
     reg [9:0]  tx_shift = 10'h3FF;
     reg [3:0]  tx_sub   = 4'd0;
     reg [3:0]  tx_bit   = 4'd0;

     assign uart_tx = tx_shift[0];

     // TX line drive:
     //   tx_shift is a 10-bit frame {stop, data[7:0], start}.
     //   We shift right (toward bit 0) once per bit-time (16 ticks).
     //   uart_tx is continuously driven from tx_shift[0].


     // Response-byte mux:
     //   Maps tx_index (0..4) to the corresponding response field.
     //   This keeps the TX engine generic: it simply asks for the next byte.

     function [7:0] resp_byte;
          input [2:0] idx;
          begin
               case (idx)
               3'd0:  resp_byte = 8'h56;
               3'd1:  resp_byte = resp_status;
               3'd2:  resp_byte = resp_addr;
               3'd3:  resp_byte = resp_data;
               default: resp_byte = resp_chk;
               endcase
          end
     endfunction

     // UART TX engine:
     //   - Idle state drives uart_tx HIGH (tx_shift = 10'h3FF).
     //   - When tx_req is asserted, we latch into tx_busy and send 5 bytes:
     //       56 STATUS ADDR DATA CHK
     //   - Bit timing is driven by tick16; we advance one bit each 16 ticks.
     //   - tx_index selects which byte in the 5-byte response we are sending.
     //
     // Key robustness point:
     //   tx_req is treated as a level (latched request) and is cleared once
     //   tx_busy is observed. This avoids missing a 1-cycle pulse.

     always @(posedge clk)
     begin
          if (rst_i)
          begin
               tx_busy  <= 1'b0;
               tx_index <= 3'd0;
               tx_shift <= 10'h3FF;
               tx_sub   <= 4'd0;
               tx_bit   <= 4'd0;
          end
          else if (tick16)
          begin
               if (!tx_busy)
               begin
                    tx_shift <= 10'h3FF;

                    if (tx_req)
                    begin
                         tx_busy  <= 1'b1;
                         tx_index <= 3'd0;
                         tx_sub   <= 4'd0;
                         tx_bit   <= 4'd0;
                         tx_shift <= { 1'b1, resp_byte(3'd0), 1'b0 };
                    end
               end
               else
               begin
                    tx_sub <= tx_sub + 1'b1;

                    if (tx_sub == 4'd15)
                    begin
                         tx_sub   <= 4'd0;
                         tx_shift <= { 1'b1, tx_shift[9:1] };
                         tx_bit   <= tx_bit + 1'b1;

                         if (tx_bit == 4'd9)
                         begin
                              tx_bit <= 4'd0;

                              if (tx_index == 3'd4)
                              begin
                                   tx_busy  <= 1'b0;
                                   tx_shift <= 10'h3FF;
                              end
                              else
                              begin
                                   tx_index <= tx_index + 1'b1;
                                   tx_shift <= { 1'b1, resp_byte(tx_index + 3'd1), 1'b0 };
                              end
                         end
                    end
               end
          end
     end

     // --------------------------------------------------------
     // Protocol FSM + TX request latch
     // --------------------------------------------------------
     // Protocol decode / response generation:
     //   - This FSM consumes 5 received bytes following the 0x55 SYNC.
     //   - The fields (op/addr/data) are latched as they arrive.
     //   - On CHK byte reception, we validate the request checksum:
     //         (0x55 ^ op ^ addr ^ data) == rx_byte
     //   - If valid, we perform the register read/write and build a response:
     //         0x56 status addr data chk
     //       where chk = 0x56 ^ status ^ addr ^ data
     //   - Finally we assert tx_req (if TX is idle) to launch the response.
     //
     // Status codes (as implemented here):
     //   0x00 : OK
     //   0x01 : Unsupported OP
     //   0xFF : Bad checksum

     always @(posedge clk)
     begin
          if (rst_i)
          begin
               p_state     <= P_IDLE;
               op          <= 8'h00;
               addr        <= 8'h00;
               data        <= 8'h00;

               test_reg    <= 8'h5A;

               resp_status <= 8'h00;
               resp_addr   <= 8'h00;
               resp_data   <= 8'h00;
               resp_chk    <= 8'h00;

               tx_req      <= 1'b0;
          end
          else
          begin
               if (tx_busy)
               begin
                    tx_req <= 1'b0;
               end

               if (rx_valid)
               begin
                    case (p_state)
                    P_IDLE:
                    begin
                         if (rx_byte == 8'h55)
                         begin
                              p_state <= P_OP;
                         end
                    end

                    P_OP:
                    begin
                         op      <= rx_byte;
                         p_state <= P_ADDR;
                    end

                    P_ADDR:
                    begin
                         addr    <= rx_byte;
                         p_state <= P_DATA;
                    end

                    P_DATA:
                    begin
                         data    <= rx_byte;
                         p_state <= P_CHK;
                    end

                    P_CHK:
                    begin
                         status_n = 8'h00;
                         data_n   = 8'h00;

                         if ((8'h55 ^ op ^ addr ^ data) == rx_byte)
                         begin
                              if (op == 8'h01)
                              begin
                                   if (addr == TEST_ADDR)
                                   begin
                                        data_n = test_reg;
                                   end
                                   else
                                   begin
                                        data_n = 8'h00;
                                   end
                              end
                              else if (op == 8'h02)
                              begin
                                   if (addr == TEST_ADDR)
                                   begin
                                        test_reg <= data;
                                        data_n    = data;
                                   end
                                   else
                                   begin
                                        data_n = 8'h00;
                                   end
                              end
                              else
                              begin
                                   status_n = 8'h01;
                              end
                         end
                         else
                         begin
                              status_n = 8'hFF;
                         end

                         resp_status <= status_n;
                         resp_addr   <= addr;
                         resp_data   <= data_n;
                         resp_chk    <= (8'h56 ^ status_n ^ addr ^ data_n);

                         if (!tx_busy)
                         begin
                              tx_req <= 1'b1;
                         end

                         p_state <= P_IDLE;
                    end

                    default:
                    begin
                         p_state <= P_IDLE;
                    end
                    endcase
               end
          end
     end

endmodule

`default_nettype wire
