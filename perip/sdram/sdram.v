module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,

  inout [15:0] dq
);
//=============================================================================
//recode the open raw
// ============================================================================
// 如下两个reg 记录打开的 row
// 记录有哪几个 banck 打开了
reg [3:0] bank_open_r;  
// 记录具体打开的是哪个 bank 的 哪个 row
reg [12:0] active_row_r [0:3];
//=============================================================================
// command parse
// ============================================================================
wire [3:0] command;
assign command = {cs, ras, cas, we};

wire cmd_nop       = (command == 4'b0111);
wire cmd_active    = (command == 4'b0011);
wire cmd_read      = (command == 4'b0101);
wire cmd_write     = (command == 4'b0100);

wire cmd_precharge = (command == 4'b0010);
wire cmd_refresh   = (command == 4'b0001);
wire cmd_load_mode = (command == 4'b0000);

// wait counter for reading
reg [2:0] cnt;

// read number
reg [1:0] read_num;

//reg [12:0] addr_row_r;
reg [12:0] addr_col_r;
reg [1:0] addr_bank_r;
reg [3:0] dqm_r;

wire [12:0] addr_col;
wire [12:0] addr_row;
wire [1:0] addr_bank;

//assign addr_row  = cmd_active ? a : active_row_r[addr_bank];
assign addr_row = active_row_r[addr_bank];

assign addr_col  = (cmd_read | cmd_write) ? a : addr_col_r;
assign addr_bank = (cmd_read | cmd_write) ? ba : addr_bank_r;

// cpu write data
reg [31:0] wdata;

// only cas latency, burst length
reg [5:0] mode_reg;   // bl = 2 ** 1, cas = 2
wire [2:0] bl = mode_reg[2:0];   // 1
wire [2:0] cl = mode_reg[5:3];

//=============================================================================
// FSM 
// ============================================================================
parameter [2:0] idle = 3'd0,  load_mode = 3'd1, active = 3'd2, 
                read = 3'd3, read1 = 3'd4, 
                write = 3'd5, write1 = 3'd6; 

reg [2:0] state, next; 

always @(posedge clk)
  if (!cke)
    state <= idle;
  else 
    state <= next;

always @(*) begin
  next = idle;
  case (state)
    idle: 
      if (cmd_load_mode) next = load_mode;
      else if (cmd_active) next = active;
      else if (cmd_read) next = read;
      else if (cmd_write) next = write;
      else next = idle;

    load_mode:
      if (cmd_active) 
        next = active;
      else if (cmd_load_mode)
        next = load_mode;
      else
        next = idle;

    active:
      if (cmd_write)
        next = write;
      else if (cmd_read)
        next = read;
      else
        next = active;

    // not read
    read:
      if (cnt == cl - 2)
        next = read1;
      else
        next = read;

    // now read
    read1: 
      if (read_num != bl[1:0])
        next = read1;
      else
        next = idle;

    // no delayer between write
    write:
      if (cmd_nop)   // sdram_axi_core.v STATE_WRITE1 will send a cmd_nop
        next = write1;
      else
        next = write;

    write1:
      next = idle;

    default:;
  endcase
end

// ----------------------------------------------------------------------------
// accept signals along with command
// ----------------------------------------------------------------------------
// set mode register
always @(posedge clk) begin
  if (next == load_mode)
    mode_reg <= {a[6:4], a[2:0]};
end
 
integer idx;
always @(posedge clk) begin
  if ( cmd_refresh || (cmd_precharge && a[10]) ) begin

    for (idx=0; idx<4; idx=idx+1)
      active_row_r[idx] <= 13'b0;

    bank_open_r <= 4'b0;
  end else if (cmd_precharge && !a[10]) begin
      bank_open_r[ba] <= 1'b0;
      //active_row_r[ba] <= 1'b0;
  end
end
// along with cmd_active also has addr_row and addr_bank
// but only need addr_row 
always @(posedge clk) begin
  if (cmd_active) begin
    //addr_row_r <= a;
    active_row_r[ba] <= a;
    bank_open_r[ba] <= 1'b1;
  end
end

// latch addr_col and addr_bank witn cmd_read and wirte
// no need to latch dqm with cmd_read, casue dqm is all 0
always @(posedge clk) begin
  if (cmd_read || cmd_write) begin
    addr_col_r <= a;
    addr_bank_r <= ba;
  end
end

always @(posedge clk) begin
  if (next == write) 
    dqm_r[1:0] <= dqm; 
  else if (next == write1)
    dqm_r[3:2] <= dqm; 
end

// cnt is just wait, as cas
always @(posedge clk) begin 
  if (!cke) 
    cnt <= 0;
  else if (state == read) 
    cnt <= cnt + 1;
  else 
    cnt <= 0;
end

// read_num is a counter for every read number;
// if a cmd_read coming along with a read, then it will reset to 0;
always @(posedge clk)
  if (!cke) 
    read_num <= 0;
  else if (cmd_read)
    read_num <= 0;
  else if (state == read1)
    read_num <= read_num + 1;
  else
    read_num <= 0;


always @(posedge clk) begin
  if (next == write)
    wdata[15:0] <=  dq;
  else if (next == write1)
    wdata[31:16] <=  dq;
end


import "DPI-C" function void sdram_read(input int addr, output int data);
import "DPI-C" function void sdram_write(input int addr, input int data, input byte mask);
//=============================================================================
// read 
// ============================================================================
//wire [31:0] rdata_t;
reg [31:0] rdata_t;
wire [31:0] raddr;
assign raddr = {7'b0, addr_row, addr_bank, addr_col[8:1], 2'b0};
//assign raddr = {7'b0, active_row_r[addr_bank], addr_bank, addr_col[8:1], 2'b0};
always @(posedge clk) begin
  if (state == read && next == read1)
    sdram_read(raddr, rdata_t); 
end

// 向外发送数据, 即被读时
wire dioen;
assign dioen = (state == read1);
wire [15:0] rdata;
assign rdata = (read_num == 0) ? rdata_t[15:0] : rdata_t[31:16];

assign dq = dioen ? rdata : 16'bz;
//=============================================================================
// write 
// ============================================================================
wire [31:0] waddr;
assign waddr = {7'b0, addr_row, addr_bank, addr_col[8:1], 2'b00};
//assign waddr = {7'b0, active_row_r[addr_bank], addr_bank, addr_col[8:1], 2'b0};

wire [7:0] wmask;
assign wmask = {4'b0000, ~dqm_r};


always @(posedge clk) begin
  if (state == write1) 
    sdram_write(waddr, wdata, wmask);
end

endmodule
