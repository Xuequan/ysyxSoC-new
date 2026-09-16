
module vga_ctrl(
  input         pclk,
  input         reset,
  input [23:0]  vga_data,
  output [9:0]  h_addr,
  output [9:0]  v_addr,
  output        hsync,
  output        vsync,
  output        valid,
  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b
);

// 640X480 分辨率下的VGA参数设置
parameter   h_frontporch = 96;
parameter   h_active = 144;
parameter   h_backporch = 784;
parameter   h_total = 800;

parameter   v_frontporch = 2;
parameter   v_active = 35;
parameter   v_backporch = 315;
parameter   v_total = 525;

// 像素计数值
reg [9:0] x_cnt;
reg [9:0] y_cnt;
wire      h_valid;
wire      v_valid;

always @(posedge pclk) 
  if (reset == 1'b1)
    x_cnt <= 1;
  else
  begin
    if (x_cnt == h_total)
      x_cnt <= 1;
    else 
      x_cnt <= x_cnt + 10'd1;
  end 

always @(posedge pclk) 
  if (reset == 1'b1)
    y_cnt <= 1;
  else begin
    if (y_cnt == v_total && x_cnt == h_total)
      y_cnt <= 1;
    else if (x_cnt == h_total)
      y_cnt <= y_cnt + 10'd1;
  end
// 生成同步信号
assign hsync = (x_cnt > h_frontporch);
assign vsync = (y_cnt > v_frontporch);

// 生成消隐信号
assign h_valid = (x_cnt > h_active) && (x_cnt <= h_backporch);
assign v_valid = (y_cnt > v_active) && (y_cnt <= v_backporch);
assign valid = h_valid && v_valid;

// 计算当前有效像素坐标
assign h_addr = h_valid ? (x_cnt - 10'd145) : {10{1'b0}};
assign v_addr = v_valid ? (y_cnt - 10'd36)  : {10{1'b0}};

// 设置输出的颜色值
assign vga_r = vga_data[23:16];
assign vga_g = vga_data[15:8];
assign vga_b = vga_data[7:0];

endmodule

module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

reg [23:0] vga_buffer [32'h4B000];
reg ready;

wire [9:0] h_addr;
wire [9:0] v_addr;

assign in_pready = ready;

always @(posedge clock) begin
  if (reset) begin
    ready <= 0;
  end
  else if (in_pwrite && in_penable && in_psel) begin
    vga_buffer[{10'b0, in_paddr[23:2]}] <= in_pwdata[23:0];
    ready <= 1;
  end
  else
    ready <= 0;
end

wire [31:0] pixel_index = ( {22'b0, v_addr} << 9 ) + ({22'b0, v_addr} << 7) + {22'b0, h_addr};
wire [23:0] vga_data = vga_buffer[pixel_index];

vga_ctrl #(
  .h_frontporch (96),
  .h_active (144),
  .h_backporch (784),
  .h_total  (800),
  .v_frontporch (2),
  .v_active (35),
  .v_backporch (515),
  .v_total (525))
u_vga_ctrl(
  .pclk (clock),
  .reset(reset),
  .vga_data(vga_data),
  .h_addr(h_addr),
  .v_addr(v_addr),
  .hsync (vga_hsync),
  .vsync (vga_vsync),
  .valid (vga_valid),
  .vga_r (vga_r),
  .vga_g (vga_g),
  .vga_b (vga_b)
);

endmodule


