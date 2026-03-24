// ------------------------------------------------------------
// UPduino UART TX heartbeat test
// ------------------------------------------------------------
// Transmits byte 0x55 repeatedly at 9600 baud.
// NoI: no RX, no registers, no protocol.
// Purpose: prove FPGA -> FTDI TX path and clock are alive.
// ------------------------------------------------------------

module upduino_uart_tx_heartbeat
(
     input  wire clk_12m,
     output reg  uart_tx
);

     localparam integer CLK_HZ   = 12_000_000;
     localparam integer BAUD     = 9_600;
     localparam integer BAUD_DIV = CLK_HZ / BAUD;

     // send 0x55
     localparam [7:0] TX_BYTE = 8'h55;

     reg [15:0] baud_cnt;
     reg [3:0]  bit_cnt;
     reg [9:0]  shift;
     reg        busy;

     // simple slow gap between bytes
     reg [23:0] gap_cnt;

     initial
     begin
          uart_tx = 1'b1;
          busy    = 1'b0;
          baud_cnt= 16'd0;
          bit_cnt = 4'd0;
          gap_cnt = 24'd0;
          shift   = 10'h3FF;
     end

     always @(posedge clk_12m)
     begin
          if (!busy)
          begin
               uart_tx <= 1'b1;

               // wait ~0.5 s between bytes
               if (gap_cnt == 24'd6_000_000)
               begin
                    gap_cnt <= 24'd0;
                    shift   <= {1'b1, TX_BYTE[7:0], 1'b0};
                    baud_cnt<= BAUD_DIV;
                    bit_cnt <= 4'd0;
                    busy    <= 1'b1;
               end
               else
                    gap_cnt <= gap_cnt + 1'b1;
          end
          else
          begin
               if (baud_cnt == 0)
               begin
                    uart_tx <= shift[0];
                    shift   <= {1'b1, shift[9:1]};
                    baud_cnt<= BAUD_DIV;

                    if (bit_cnt == 4'd9)
                    begin
                         busy    <= 1'b0;
                         bit_cnt <= 4'd0;
                    end
                    else
                         bit_cnt <= bit_cnt + 1'b1;
               end
               else
                    baud_cnt <= baud_cnt - 1'b1;
          end
     end

endmodule
