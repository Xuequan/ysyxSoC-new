/* gpio_in (cpu 的输入信号，用来读取拨码开关）
*  gpio_out (cpu 的输出信号，用来驱动 LED）
*/
module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

// -------------------------------------------------
// apb signals
// --------------------------------------------------
wire choose_leds;
assign choose_leds = in_paddr >= 32'h1000_2000 
                  && in_paddr <= 32'h1000_2003;
// 拨码开关
wire choose_sw;
assign choose_sw = in_paddr >= 32'h1000_2004 
                  && in_paddr <= 32'h1000_2007;
// 7段数码管
wire choose_seg;
assign choose_seg = in_paddr >= 32'h1000_2008 
                  && in_paddr <= 32'h1000_200b;

wire write_req;
assign write_req = in_pwrite && in_psel && in_penable;
wire read_req;
assign read_req = !in_pwrite && in_psel && in_penable;
// -------------------------------------------------
// register for LED 
// --------------------------------------------------
reg [15:0] leds;
reg [3:0] seg [7:0];

// 设定npc 传入的数据只有低16bit有用
always @(posedge clock) begin
  if (reset) leds <= 16'd0;
  else if (write_req && choose_leds) begin
    if (in_pstrb[0])
      leds[7:0] <= in_pwdata[7:0];
    if (in_pstrb[1])
      leds[15:8] <= in_pwdata[15:8];
  end
end

// 7段数码管
always @(posedge clock) begin
  if (reset) begin 
    seg[0] <= 4'd0;
    seg[1] <= 4'd0;
    seg[2] <= 4'd0;
    seg[3] <= 4'd0;
    seg[4] <= 4'd0;
    seg[5] <= 4'd0;
    seg[6] <= 4'd0;
    seg[7] <= 4'd0;
  end
  else if (write_req && choose_seg) begin
    if (in_pstrb[0])  
      {seg[1], seg[0]} <= in_pwdata[7:0];
    if (in_pstrb[1])
      {seg[3], seg[2]} <= in_pwdata[15:8];
    if (in_pstrb[2])  
      {seg[5], seg[4]} <= in_pwdata[23:16];
    if (in_pstrb[3])
      {seg[7], seg[6]} <= in_pwdata[31:24];
  end
end


wire [7:0] segs [15:0];
assign segs[0] = 8'b11111101; 
assign segs[1] = 8'b01100000; 
assign segs[2] = 8'b11011010; 
assign segs[3] = 8'b11110010; 
assign segs[4] = 8'b01100110; 
assign segs[5] = 8'b10110110; 
assign segs[6] = 8'b10111110; 
assign segs[7] = 8'b11100000; 
assign segs[8] = 8'b11111110; 
assign segs[9] = 8'b11110110; 
assign segs[10] = 8'b11101110; 
assign segs[11] = 8'b00111110; 
assign segs[12] = 8'b10011100; 
assign segs[13] = 8'b01111010; 
assign segs[14] = 8'b10011110; 
assign segs[15] = 8'b10001110; 

function [7:0] get_seg_decode (input [3:0] number);
  case (number)
    4'h0: get_seg_decode = segs[0];
    4'h1: get_seg_decode = segs[1];
    4'h2: get_seg_decode = segs[2];
    4'h3: get_seg_decode = segs[3];
    4'h4: get_seg_decode = segs[4];
    4'h5: get_seg_decode = segs[5];
    4'h6: get_seg_decode = segs[6];
    4'h7: get_seg_decode = segs[7];
    4'h8: get_seg_decode = segs[8];
    4'h9: get_seg_decode = segs[9];
    4'ha: get_seg_decode = segs[10];
    4'hb: get_seg_decode = segs[11];
    4'hc: get_seg_decode = segs[12];
    4'hd: get_seg_decode = segs[13];
    4'he: get_seg_decode = segs[14];
    4'hf: get_seg_decode = segs[15];
  default:
          get_seg_decode = 8'b00000000;
  endcase
endfunction


assign gpio_seg_0 = ~get_seg_decode(seg[0]);
assign gpio_seg_1 = ~get_seg_decode(seg[1]);
assign gpio_seg_2 = ~get_seg_decode(seg[2]);
assign gpio_seg_3 = ~get_seg_decode(seg[3]);
assign gpio_seg_4 = ~get_seg_decode(seg[4]);
assign gpio_seg_5 = ~get_seg_decode(seg[5]);
assign gpio_seg_6 = ~get_seg_decode(seg[6]);
assign gpio_seg_7 = ~get_seg_decode(seg[7]);

assign gpio_out = leds;

assign in_pready = 1'b1;

assign in_pslverr = 1'b0;

// 读出 switch button 的状态以及 leds 
// 虽说数码管通常只写不读，但标准的APB设备的读通道最好补齐 choose_seg, 方便CPU
// 读回校验
assign in_prdata = choose_sw   ? {16'b0, gpio_in} :     
                   choose_leds ? {16'b0, leds} : 
                   choose_seg  ? {seg[7], seg[6], seg[5], seg[4], seg[3], seg[2], seg[1], seg[0]} : 32'b0;

endmodule
