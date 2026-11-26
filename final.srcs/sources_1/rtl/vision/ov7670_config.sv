// OV7670 VGA RGB565 configuration. Register meanings: OmniVision DS v1.01.
// Window and RGB matrix numeric values cross-checked against upstream Linux
// drivers/media/i2c/ov7670.c. Controller/state machine written for this project.
module ov7670_config #(
    parameter integer QUARTER_CYCLES=63,
    parameter integer RESET_CYCLES=250000,  // 10 ms at 25 MHz
    parameter integer SETTLE_CYCLES=7500000 // 300 ms after changes
)(
    input wire clk,rst,color_bars,
    input wire sda_in,
    output wire scl_low,sda_low,
    output wire reset_n,
    output reg ready,failed,
    output reg [15:0] sensor_id,
    output reg [3:0] error_code
);
    localparam HOLD=0,WAIT_RESET=1,ISSUE=2,WAIT_BUS=3,DELAY=4,FINISHED=5;
    reg [2:0] state;
    reg [23:0] delay_count;
    reg [5:0] index;
    reg bars_hold,start,read;
    reg [7:0] address,value;
    wire busy,done,nack;
    wire [7:0] returned;
    sccb_master #(.QUARTER_CYCLES(QUARTER_CYCLES)) bus(
        .clk(clk),.rst(rst),.start(start),.read(read),.address(address),.write_data(value),
        .sda_in(sda_in),.scl_low(scl_low),.sda_low(sda_low),.busy(busy),
        .done(done),.nack(nack),.read_data(returned));
    assign reset_n=!rst && state!=HOLD;
    // First reset, identify, then explicit format/clock/window/automatic controls.
    // CLKRC=1, PLL bypass -> 12.5 MHz PCLK from the forwarded 25 MHz XCLK.
    function automatic [15:0] setting(input [5:0] i,input bit bars);
        case(i)
            0:setting=16'h1280;
            1:setting=16'h0a00; 2:setting=16'h0b00;
            3:setting=16'h1204; 4:setting=16'h1101; 5:setting=16'h6b0a;
            6:setting=16'h0c00; 7:setting=16'h3e00; 8:setting=16'h1500;
            9:setting=16'h1713;10:setting=16'h1801;11:setting=16'h32b6;
            12:setting=16'h1902;13:setting=16'h1a7a;14:setting=16'h030a;
            15:setting=16'h8c00;16:setting=16'h0400;17:setting=16'h40d0;
            18:setting=16'h1438;19:setting=16'h4fb3;20:setting=16'h50b3;
            21:setting=16'h5100;22:setting=16'h523d;23:setting=16'h53a7;
            24:setting=16'h54e4;25:setting=16'h589e;
            26:setting=16'h3dc0;27:setting=16'h13e7;28:setting=16'h1e00;
            29:setting=16'hb084; // reserved reg, needed for correct color (common OV7670 init)
            30:setting={8'h42,bars?8'h08:8'h00};
            31:setting=16'h1200;32:setting=16'h4000;
            default:setting=0;
        endcase
    endfunction
    wire [15:0] entry=setting(index,bars_hold);
    always @(posedge clk) begin
        start<=0;
        if(rst) begin
            state<=HOLD;delay_count<=0;index<=0;bars_hold<=color_bars;
            ready<=0;failed<=0;sensor_id<=0;error_code<=0;
            start<=0;read<=0;address<=0;value<=0;
        end else if(state==FINISHED && bars_hold!=color_bars) begin
            state<=HOLD;delay_count<=0;ready<=0;failed<=0;index<=0;bars_hold<=color_bars;
            error_code<=0;
        end else case(state)
            HOLD: if(delay_count==RESET_CYCLES-1) begin delay_count<=0;state<=WAIT_RESET;end
                  else delay_count<=delay_count+1'b1;
            WAIT_RESET: if(delay_count==RESET_CYCLES-1) begin delay_count<=0;state<=ISSUE;end
                        else delay_count<=delay_count+1'b1;
            ISSUE: if(!busy) begin
                address<=entry[15:8];value<=entry[7:0];
                read<=(index==1 || index==2 || index>=31);start<=1;state<=WAIT_BUS;
            end
            WAIT_BUS: if(done) begin
                if(index==1) sensor_id[15:8]<=returned;
                if(index==2) sensor_id[7:0]<=returned;
                if(nack || (index==1 && returned!=8'h76) || (index==2 && returned!=8'h73) ||
                   (index==31 && returned!=8'h04) || (index==32 && returned!=8'hd0)) begin
                    failed<=1;ready<=0;state<=FINISHED;
                    error_code<=nack?1:(index<3?2:3);
                end else if(index==0) begin index<=1;delay_count<=0;state<=WAIT_RESET;end
                else if(index==32) begin delay_count<=0;state<=DELAY;end
                else begin index<=index+1'b1;state<=ISSUE;end
            end
            DELAY: if(delay_count==SETTLE_CYCLES-1) begin ready<=1;state<=FINISHED;end
                   else delay_count<=delay_count+1'b1;
            default: begin end
        endcase
    end
endmodule
