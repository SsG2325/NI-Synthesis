module tt_um_NI(
	input  	wire 	[7:0] ui_in,    // Dedicated inputs
    	output 	wire 	[7:0] uo_out,   // Dedicated outputs
   	input  	wire 	[7:0] uio_in,   // IOs: Input path
  	output	 wire	[7:0] uio_out,  // IOs: Output path
   	output 	wire 	[7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
	input	wire		ena,
	input	wire		rst_n,
	input	wire		clk
);

	wire rst;
	wire [1:0]dest_add;
	wire [31:0]data_in;
	wire proc_valid;
	reg proc_ready;
	reg [31:0]data_out;
	reg data_valid;
	wire proc_ready_in;
	wire [7:0]flit_in;
	wire flit_in_valid;
	wire noc_ready;
	/* verilator lint_off UNUSEDSIGNAL */reg [7:0]flit_out;/* verilator lint_on UNUSEDSIGNAL */
	reg flit_valid;

	assign rst = ~rst_n;
	assign dest_add = ui_in[7:6];
	assign proc_valid = ui_in[5];
	assign proc_ready_in = ui_in[4];
	assign flit_in_valid = ui_in[3];
	assign noc_ready = ui_in[2];

	assign data_in = {ui_in,uio_in,uio_in, ui_in};
	assign flit_in = uio_in[7:0];
	assign	{uo_out[7:5], uio_out, uio_oe}	= data_out[18:0];
	assign uo_out[4:0] = flit_out[4:0];
	/* verilator lint_off UNUSEDSIGNAL */
	assign uio_out[0] = proc_ready;
	assign uio_out[1] = data_valid;
	assign uio_out[2] = flit_valid;
	/* verilator lint_on UNUSEDSIGNAL */

	/* verilator lint_off UNUSEDSIGNAL */ wire _unused = &{ena, data_out[31:19], 1'b0}; /* verilator lint_on UNUSEDSIGNAL */

parameter HEADER = 6'b101111;
parameter TAILER = 8'b11111111;

/* verilator lint_off UNUSEDSIGNAL */ reg	[47:0]	packet_buffer_in;/* verilator lint_on UNUSEDSIGNAL */
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
								flit_out 	<= packet_buffer_out[7:0];
							end
							else begin
								flit_out 	<= flit_b;
							end
						end
						2: begin
							if(~(|flit_c)) begin
								flit_out	<= packet_buffer_out[7:0];
								state_out 	<= SEND_TAIL;
							end
							else begin
								flit_out 	<= flit_c;
							end
						end
						3: begin
							if(~(|flit_d)) begin
								state_out 	<= SEND_TAIL;
								flit_out 	<= packet_buffer_out[7:0];
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
