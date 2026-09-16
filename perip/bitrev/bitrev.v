module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
	parameter [1:0] idle = 2'b00, receive = 2'b01, send = 2'b10;
	reg [1:0] state, next;
	reg [3:0] counter;
	reg [7:0] data;

	assign miso = ss ? 1'b1 : 
		( (counter == 4'd7) ? data[0] : data[ counter[2:0] +1 ] );

	always @(posedge sck) begin
		if (ss) 
			state <= idle;
		else 
			state <= next;
	end
	
	always @(*) begin
		next = idle;
		case (state)
			idle: 
				if (!ss) next = receive;
				else     next = idle;
			receive:
				if (counter != 4'd7)	next = receive;
				else 									next = send;
			send:
				if (counter != 4'd8)	next = send;
				else 									next = idle;
			default:;	
		endcase
	end			
	always @(posedge sck) begin
		if (ss) counter <= 4'd0; 
		else begin
			case ({state, next})
				{idle, receive} : 	 counter <= 4'd0;
				{receive, receive} : counter <= counter + 4'd1;
				{receive, send}:     counter <= 4'd0;
				{send, send}: 			 counter <= counter + 4'd1;
				default:						 counter <= 4'd0;
			endcase
		end
	end
	always @(posedge sck) begin
		if (ss) data <= 8'd0;
		else if (next == receive)
			data <= {data[6:0], mosi};   
	end
	
endmodule
