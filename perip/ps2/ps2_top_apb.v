module ps2_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  input         ps2_clk,
  input         ps2_data
);

reg ready_r;
//reg overflow_r;
reg [9:0] buffer;
reg [7:0] fifo[7:0];
reg [2:0] w_ptr, r_prt;
reg [3:0] count;

// detect falling edge of ps2_clk;
reg [2:0] ps2_clk_sync;
always @(posedge clock) begin
  ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
end

wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

always @(posedge clock) begin
  if (reset) begin
    count <= 0;
    w_ptr <= 0;
    r_prt <= 0;
    //overflow_r <= 0;
    ready_r <= 0;
  end
  else begin
    if (ready_r) begin
      r_prt <= r_prt + 3'b1;
      if (w_ptr == (r_prt + 1'b1) )  // enpty
        ready_r <= 1'b0;
    end 

    if (sampling) begin
      if (count == 4'd10) begin
        count <= 0;   // 重置
        if ( (buffer[0] == 0) && (ps2_data) && (^buffer[9:1]) ) begin
          
          $display("receive %x", buffer[8:1]);

          fifo[w_ptr] <= buffer[8:1];
          w_ptr <= w_ptr + 3'b1;
          ready_r <= 1'b1;
          //overflow_r <= overflow_r | (r_prt == (w_ptr + 3'b1));
        end 
      end 
    end else begin
      buffer[count] <= ps2_data;
      count <= count + 3'b1;
    end 
  end // end if(sampling)
end

assign in_prdata = {24'b0, fifo[r_prt]};
assign in_pready = ready_r;
assign in_pslverr = 0;

endmodule
