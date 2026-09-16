module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

reg [2:0] cnt;
wire [2:0] cnt7 = 3'd7;
wire [2:0] cnt5 = 3'd5;
wire [2:0] cnt1 = 3'd1;

reg [7:0] cmd;
wire is_rd_cmd;
wire is_wr_cmd;

assign is_rd_cmd = (cmd == 8'hEB);
assign is_wr_cmd = (cmd == 8'h38);

parameter [2:0] INIT = 3'd0, ENT_QPI = 3'd1, 
								IDLE = 3'd2,
								REC_CMD = 3'd3, 
								REC_ADR = 3'd4,
								RD_DELAY = 3'd5, SEND_DAT = 3'd6, 
								REC_DAT = 3'd7;
reg [2:0] state, next;

always @(posedge sck or posedge ce_n) 
	if (ce_n && state != INIT) 
		state <= IDLE;
	else if (ce_n && state == INIT)
		state <= INIT;
	else 			
		state <= next;

always @* begin
	next = INIT;
	case (state) 
		INIT:
			if (!ce_n) 
				next = ENT_QPI;
			else 
				next = INIT;

		ENT_QPI:
			if (cnt == cnt7)
				next = IDLE;
			else 
				next = ENT_QPI;

		IDLE:   // this is QPI IDLE
			if (!ce_n) 
				next = REC_CMD;
			else 
				next = IDLE;

		REC_CMD:
			if (cnt == cnt1)
				next = REC_ADR;
			else 
				next = REC_CMD;

		REC_ADR:
			if (cnt == cnt5 && is_rd_cmd)
				next = RD_DELAY;
			else if (cnt == cnt5 && is_wr_cmd)
				next = REC_DAT;
			else if (cnt == cnt5) begin
				$fwrite(32'h80000002, "Assertion failed: Unsupport command '%xh', only support'38h' and 'EBh'\n", cmd);
				$fatal;
			end 
			else
				next = REC_ADR;
			
		RD_DELAY: 
			if (cnt == cnt5)
				next = SEND_DAT;
			else 
				next = RD_DELAY;

		SEND_DAT:
			if (cnt == cnt7)
				next = IDLE;
			else 
				next = SEND_DAT;

		REC_DAT:
			if (cnt == cnt7)
				next = IDLE;
			else 
				next = REC_DAT;
		
		default:;	
	endcase
end

always @(posedge sck or posedge ce_n) begin
	if (ce_n) 
		cnt <= 3'd0;
	else begin
		cnt <= 3'd0;
		case ({state, next})
			{INIT, ENT_QPI} : cnt <= 3'd0;

			{ENT_QPI, ENT_QPI} : cnt <= cnt + 3'd1;

			{ENT_QPI, IDLE} : cnt <= 3'd0;

			{IDLE, IDLE} : cnt <= 3'd0;

			{IDLE, REC_CMD} : cnt <= 3'd0;

			{REC_CMD, REC_CMD} : cnt <= cnt + 3'd1;

			{REC_CMD, REC_ADR} : cnt <= 3'd0;

			{REC_ADR, REC_ADR} : cnt <= cnt + 3'd1;

			{REC_ADR, RD_DELAY} : cnt <= 3'd0;

			{RD_DELAY, RD_DELAY} : cnt <= cnt + 3'd1;

			{RD_DELAY, SEND_DAT} : cnt <= 3'd0;

			{SEND_DAT, SEND_DAT} : cnt <= cnt + 3'd1;

			{SEND_DAT, IDLE} : cnt <= 3'd0;

			{REC_ADR, REC_DAT} : cnt <= 3'd0;

			{REC_DAT, REC_DAT} : cnt <= cnt + 3'd1;

			{REC_DAT, IDLE} : cnt <= 3'd0;
			default:;
		endcase
	end
end

always @(posedge sck or ce_n) begin
	if (ce_n) 
		cmd <= 8'd0;
	else if (next == REC_CMD) 
		cmd <= {cmd[3:0], dio};
end

reg [23:0] adr;
always @(posedge sck or ce_n) begin
	if (ce_n) 
		adr <= 24'd0;
	else if (next == REC_ADR) 
		adr <= {adr[19:0], dio};
end

reg [31:0] data_in;
always @(posedge sck) begin
	if (ce_n)	
		data_in <= 32'd0;
	else if (next == REC_CMD)  
		data_in <= 32'd0;
	else if (next == REC_DAT)
		if (state == REC_ADR) 
			data_in[7:4] <= dio;
		else if (cnt == 3'd0)
			data_in[3:0] <= dio;
		else if (cnt == 3'd1)
			data_in[15:12] <= dio;
		else if (cnt == 3'd2)
			data_in[11:8] <= dio;
		else if (cnt == 3'd3)
			data_in[23:20] <= dio;
		else if (cnt == 3'd4)
			data_in[19:16] <= dio;
		else if (cnt == 3'd5)
			data_in[31:28] <= dio;
		else if (cnt == 3'd6)
			data_in[27:24] <= dio;
end

reg [31:0] data_o;
//wire [31:0] data_o;
wire [3:0] douten = 4'b1111;
wire [3:0] dio_t;
assign dio_t = ( {4{ next == SEND_DAT && cnt == 0}} & data_o[7:4] )
					| ({4{ next == SEND_DAT && cnt == 1}} & data_o[3:0] )
					| ({4{ next == SEND_DAT && cnt == 2}} & data_o[15:12] )
					| ({4{ next == SEND_DAT && cnt == 3}} & data_o[11:8] )
					| ({4{ next == SEND_DAT && cnt == 4}} & data_o[23:20] )
					| ({4{ next == SEND_DAT && cnt == 5}} & data_o[19:16] )
					| ({4{ next == SEND_DAT && cnt == 6}} & data_o[31:28] )
					| ({4{ state == SEND_DAT && cnt == 7}} & data_o[27:24] );
assign dio[0] = douten[0] ? dio_t[0] : 1'bz;
assign dio[1] = douten[1] ? dio_t[1] : 1'bz;
assign dio[2] = douten[1] ? dio_t[2] : 1'bz;
assign dio[3] = douten[3] ? dio_t[3] : 1'bz;

import "DPI-C" function void psram_read(input int addr, output int data);
import "DPI-C" function void psram_write(input int addr, input int data, input byte len);

// len : means write bytes, 'b1 --> 1byte, 'b11 --> 2byte, 'b1111 --> 4bytes
wire [7:0] len;
assign len =  ( {8{(state == REC_DAT && cnt == 3'd1)}} & 8'b0000_0001 )
						|	( {8{(state == REC_DAT && cnt == 3'd3)}} & 8'b0000_0011 )
						| ( {8{(state == REC_DAT && cnt == 3'd7)}} & 8'b0000_1111 );

wire [31:0] psram_addr = {8'd0, adr};
always @(posedge sck or ce_n) begin
	if (next == RD_DELAY && cnt == 3'd5 ) 
		psram_read(psram_addr, data_o);
end

wire [31:0] wdata = data_in;
always @(posedge ce_n) begin
	if (state == REC_DAT)
		psram_write(psram_addr, wdata, len);
end
endmodule
