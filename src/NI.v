module NI(
	input			clk,
	input			rst,
	input		[1:0]	dest_add,
	
	//processor interface
	input		[31:0]	data_in,	//data from processor  [check]
	input			proc_valid,	//indicates data from processor is valid [check]
	output	reg		proc_ready,	//indicates NI is ready to accept new data	[check] [mips_ni]
	
	output	reg	[31:0]	data_out,	//data to processor [check]
	output	reg		data_valid,	//indicates data to the processor is valid [check]
	input			proc_ready_in,	//indicates processor is ready to accept the data [check]

	//NoC interface
	input		[7:0]	flit_in,	//flit from NoC to NI 
	input			flit_in_valid,	//indicates incoming flit to NI is valid
	//indicates if NI is ready to accept incoming flits from router

	input			noc_ready,	//indicates if router is ready to accept the flit 
	output	reg	[7:0]	flit_out,	//flit from NI to NoC
	output	reg		flit_valid	//indicates flit valid for transmission
);

parameter HEADER = 6'b101111;
parameter TAILER = 8'b11111111;

reg	[47:0]	packet_buffer_in;
reg	[47:0]	packet_buffer_out;
reg	[2:0]	flit_count_out;
reg	[2:0]	flit_count_in;
reg	[1:0]	state_out;
reg	[1:0]	state_in;

wire count_in;
assign count_in = (flit_count_in == 3'd4) ? 0 : 1;

wire count_out;
assign count_out = (flit_count_out == 3'd4) ? 0 : 1;

wire trailer_flit;
assign trailer_flit = (flit_in == 8'b11111111) ? 1 : 0;

wire [7:0]	flit_a,flit_b, flit_c, flit_d;  
assign flit_a = packet_buffer_out[15:8];
assign flit_b = packet_buffer_out[23:16];
assign flit_c = packet_buffer_out[31:24];
assign flit_d = packet_buffer_out[39:32];

localparam
	IDLE		= 2'b00,
	SEND_HEAD	= 2'b01,
	SEND_DATA	= 2'b10,
	SEND_TAIL	= 2'b11,

	RECV_HEAD	= 2'b00,
	RECV_DATA	= 2'b01,
	RECV_TAIL	= 2'b10,
	RECV_DONE	= 2'b11;

//MIPS to NI to Router
always @(posedge clk or posedge rst) begin
	if(rst) begin
		packet_buffer_out	<= 48'd0;
		state_out		<= IDLE;
		flit_count_out		<= 0;
		proc_ready		<= 1;
		flit_valid		<= 0;
	end

	else begin
		case(state_out)
			IDLE: begin
				if(proc_valid) begin
					packet_buffer_out[47:40]	<= {HEADER, dest_add};
					packet_buffer_out[39:8]		<= data_in;
					packet_buffer_out[7:0]		<= TAILER;
					proc_ready			<= 0;
					state_out			<= SEND_HEAD;
				end
			end

			SEND_HEAD: begin
				if(noc_ready) begin
					flit_out	<= packet_buffer_out[47:40];
					flit_valid	<= 1;
					flit_count_out	<= 0;
					state_out	<= SEND_DATA;
				end
			end

			SEND_DATA: begin
				if(noc_ready && count_out) begin
					case(flit_count_out)
						0: flit_out <= flit_a;
						1: begin
							if(~(|flit_b)) begin
								state_out 	<= SEND_TAIL;
								flit_out 	<= packet_buffer_out[7:0]
							end
							else begin
								flit_out 	<= flit_b;
							end
						end
						2: begin
							if(~(|flit_c)) begin
								flit_out	<= packet_buffer_out[7:0]
								state_out 	<= SEND_TAIL;
							end
							else begin
								flit_out 	<= flit_c;
							end
						end
						3: begin
							if(~(|flit_d)) begin
								state_out 	<= SEND_TAIL;
								flit_out 	<= packet_buffer_out[7:0]
							end
							else begin
								flit_out 	<= flit_d;
							end
						end
					endcase
					flit_count_out <= flit_count_out + 1;
				end
				else if(~count_out) begin
					state_out <= SEND_TAIL;
				end
			end

			SEND_TAIL: begin
				if(noc_ready) begin
					flit_out 	<= packet_buffer_out[7:0];
					state_out	<= IDLE;
					proc_ready	<= 0;
				end
			end
		endcase
	end
end

//Router to NI to MIPS
always @(posedge clk or posedge rst) begin
	if(rst) begin
		packet_buffer_in	<= 48'd0;
		state_in		<= RECV_HEAD;
		flit_count_in		<= 0;
		data_valid		<= 0;
	end

	else begin
		case(state_in)
			RECV_HEAD: begin
				if(flit_in_valid && proc_ready_in) begin
					packet_buffer_in[47:40]	<= flit_in;
					flit_count_in		<= 0;
					state_in		<= RECV_DATA;
					data_valid		<= 0;
				end
			end

			RECV_DATA: begin
				if(flit_in_valid && proc_ready_in && count_in)begin
					case(flit_count_in)
						0: packet_buffer_in[15:8]	<= flit_in;
						1: begin
							if(trailer_flit) begin
								packet_buffer_in[39:16]	<= 0;
								state_in <= RECV_TAIL;
							end
							else begin
								packet_buffer_in[23:16] <= flit_in;
							end
						end
						2: begin
							if(trailer_flit) begin
								packet_buffer_in[39:24]	<= 0;
								state_in <= RECV_TAIL;
							end
							else begin
								packet_buffer_in[31:24] <= flit_in;
							end
						end
						3: begin
							if(trailer_flit) begin
								packet_buffer_in[39:32]  <= 0;
								state_in <= RECV_TAIL;
							end
							else begin
								packet_buffer_in[39:32]  <= flit_in;
							end
						end
					endcase
					flit_count_in <= flit_count_in + 1;
				end
				else if(~count_in) begin
						state_in <= RECV_TAIL;
				end 
			end

			RECV_TAIL: begin
				if(flit_in_valid && proc_ready_in) begin
					packet_buffer_in[7:0]	<= flit_in;
					state_in		<= RECV_DONE;
				end	
			end

			RECV_DONE: begin
				data_out 	<= packet_buffer_in[39:8];
				data_valid	<= 1;
				state_in	<= RECV_HEAD;
			end
		endcase
	end
end

endmodule
