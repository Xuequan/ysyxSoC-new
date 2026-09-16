// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH 

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else
//================================== FSM ============================
// FSM control spi_top module (spi master) connecting with flash slave and 
// output with module spi_top_apb (also called wishbone bus)
// FSM is not only a controller but also a bridge between spi master and
// wishbone bus

wire choose_flash = (in_paddr >= flash_addr_start) 
								&& (in_paddr <= flash_addr_end); 

// check if ctrl[GO_BSY] has been cleared automatically
wire go_has_cleared;
// ack means signals from module spi_top are valid
wire ack;
// prdata is read data from module spi_top
wire [31:0] prdata;

parameter [3:0] idle = 4'h0,   // initial state, normal mode is always in this state
								xip_w_div = 4'h1,  // set divider 
								xip_w_ctrl = 4'h2,  // set ctrl without go_bsy bit
								xip_w_ss = 4'h3,  // set ss 
								xip_w_adr = 4'h4,  // send addr & cmd_read to spi master
								xip_w_go_bit = 4'h5,  // set go_bsy bit
								xip_r_go_bit = 4'h6,  // query go_bsy has been cleared or not
								xip_r_dat_l = 4'h7,    // read data from spi master
								xip_r_dat_h = 4'h8,    // read data from spi master
								xip_wait = 4'ha,  // wait a cycle, then can 轮询 go bit
								xip_rst_ss = 4'd9;    // reset, set ss to 0

reg [3:0] state, next; 
always @(posedge clock or posedge reset) 
	if (reset) state <= idle;
	else       state <= next;

always @(*) begin
	next = idle;
	case (state) 
		idle: if (choose_flash && !in_pwrite && in_psel && in_penable) 
						next = xip_w_div;
					else if (choose_flash && in_pwrite && in_psel && in_penable) 
					begin
						$fwrite(32'h80000002, "Assertion failed: write to flash, addr '%xh'\n", in_paddr); 
						$fatal;
					end
					else	next = idle;

	// 由于写入到 spi master 寄存器都是一个周期就好了
		xip_w_div: 
  		next = xip_w_ctrl;

		xip_w_ctrl: 
			next = xip_w_ss;

		xip_w_ss: 
			next = xip_w_adr;

		xip_w_adr: 
			next = xip_w_go_bit;

		xip_w_go_bit: 
			next = xip_wait;

		xip_wait: 
			next = xip_r_go_bit;
		
		// 读取 go bit, 轮询是否完成传输
		xip_r_go_bit: 
			if (go_has_cleared) next = xip_r_dat_l;
			else 								next = xip_r_go_bit;

		// 只要传输完成了，读数据也只要一个周期
		xip_r_dat_l: 
			next = xip_r_dat_h;

		xip_r_dat_h: 
			next = xip_rst_ss;

		xip_rst_ss: 
			next = idle;

		default:;
	endcase
end

// 这都是本增加的代码与 spi-master 的连接信号
wire  [4:0]  paddr;
wire         psel;
wire         penable;
wire         pwrite;
wire  [31:0] pwdata;
wire  [3:0]  pstrb;

// register addrss
assign paddr = ( {5{ next == xip_w_div  }} & 5'h14) 
						| ( {5{ next == xip_w_ctrl }} & 5'h10) 
						| ( {5{ next == xip_w_ss   }} & 5'h18) 
						| ( {5{ next == xip_w_adr  }} & 5'h04)   // 64bit length, so Tx1
						| ( {5{ next == xip_w_go_bit }} & 5'h10) 
						| ( {5{ next == xip_r_go_bit}} & 5'h10) 
						| ( {5{ next == xip_r_dat_l   }} & 5'h00)  // read Rx0
						| ( {5{ next == xip_r_dat_h   }} & 5'h04)  // read Rx1
						| ( {5{ next == xip_rst_ss  }} & 5'h18) 
						| ( {5{ next == idle			}} & in_paddr[4:0]);

// wb_stb_i(psel),
// wb bus select signal, for handshaking 
assign psel  = (state == idle && next == idle) ? in_psel  // not xip 
								: 1'b1;                                      // xip

// .wb_cyc_i(penable),
// valid bus cycle
assign penable  = (state == idle && next == idle) ? in_psel 
								: 1'b1;

 //.wb_we_i (pwrite),
 // write enable signal
assign pwrite = ( { next == xip_w_div  } & 1'b1) 
						| ( { next == xip_w_ctrl } & 1'b1) 
						| ( { next == xip_w_ss   } & 1'b1) 
						| ( { next == xip_w_adr  } & 1'b1) 
						| ( { next == xip_w_go_bit   } & 1'b1) 
						| ( { next == xip_r_go_bit} & 1'b0) 
						| ( { next == xip_r_dat_l  } & 1'b0) 
						| ( { next == xip_r_dat_h  } & 1'b0) 
						| ( { next == xip_rst_ss  } & 1'b1) 
						| ( { next == idle			   } & in_pwrite);

// data to be writed
assign pwdata = ( {32{ next == xip_w_div  }} & 32'h9) 
						| ( {32{ next == xip_w_ctrl }} & 32'h2240)  // set ctrl[ass] == 1
						| ( {32{ next == xip_w_ss   }} & 32'h1)    // connext flash
						| ( {32{ next == xip_w_adr  }} & {8'h03, in_paddr[23:2], 2'b0} ) 
						| ( {32{ next == xip_w_go_bit   }} & 32'h2340) 
						| ( {32{ next == xip_r_go_bit}} & 32'h0) 
						| ( {32{ next == xip_r_dat_l  }} & 32'h0) 
						| ( {32{ next == xip_r_dat_h }} & 32'h0) 
						| ( {32{ next == xip_rst_ss  }} & 32'h0) 
						| ( {32{ next == idle			}} & in_pwdata);

 // .wb_sel_i(pstrb),
assign pstrb = ( {4{ next == xip_w_div  }} & 4'b1111) 
						| ( {4{ next == xip_w_ctrl }} & 4'b0111) 
						| ( {4{ next == xip_w_ss   }} & 4'b0001) 
						| ( {4{ next == xip_w_adr  }} & 4'b1111) 
						| ( {4{ next == xip_w_go_bit   }} & 4'b0111) 
						| ( {4{ next == xip_r_go_bit}} & 4'b0000) // read not need this 
						| ( {4{ next == xip_r_dat_l  }} & 4'b0000) 
						| ( {4{ next == xip_r_dat_h  }} & 4'b0000) 
						| ( {4{ next == xip_rst_ss  }} & 4'b0001) 
						| ( {4{ next == idle			}} & in_pstrb);
		

assign go_has_cleared = (state == xip_r_go_bit) && (prdata[8] == 0) && ack;

// read data
reg [31:0] data_l;
always @(negedge clock or posedge reset) begin
	if (reset) data_l <= 32'd0;
	else if (state == xip_r_dat_l)
		data_l <= prdata; 
end

reg [31:0] data_h;
always @(negedge clock or posedge reset) begin
	if (reset) data_h <= 32'd0;
	else if (state == xip_r_dat_h)
		data_h <= prdata; 
end

wire [31:0] raw_data;
assign raw_data = {data_h[0], data_l[31:1]};
assign in_prdata = {raw_data[7:0], raw_data[15:8], raw_data[23:16], raw_data[31:24]};

assign in_pready = ( state == xip_rst_ss && next == idle) ? 1'b1   // xip mode
								 : ( state == idle && next == idle ) ? ack 
										: 1'b0;

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(paddr),
  .wb_dat_i(pwdata),

  .wb_dat_o(prdata), 

  .wb_sel_i(pstrb),
  .wb_we_i (pwrite),
  .wb_stb_i(psel),
  .wb_cyc_i(penable),

  .wb_ack_o(ack),

  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),

  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);
/*
spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(in_paddr[4:0]),
  .wb_dat_i(in_pwdata),
  .wb_dat_o(in_prdata),
  .wb_sel_i(in_pstrb),
  .wb_we_i (in_pwrite),
  .wb_stb_i(in_psel),
  .wb_cyc_i(in_penable),
  .wb_ack_o(in_pready),
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);
*/
`endif // FAST_FLASH

endmodule
