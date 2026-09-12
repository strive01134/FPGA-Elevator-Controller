`timescale 1ns / 1ps

module elevator(
    input clk,
    input reset_n,
    input BTN2, BTN1, BTN0,
    output [7:0] seg_out,
    output [3:0] com_out,
    output [3:0] motor_out
);

    lift_ctrl u_lift (
        .clk_100m(clk), .reset_n(reset_n),
        .BTN2(BTN2), .BTN1(BTN1), .BTN0(BTN0),
        .seg_out(seg_out), .com_out(com_out), .motor_out(motor_out)
    );

endmodule

module seg_encoder(
    input [3:0] code,
    output reg [7:0] seg
);
    always @(*) begin
        case(code)
            4'd0: seg <= 8'b11111100;
            4'd1: seg <= 8'b01100000;
            4'd2: seg <= 8'b11011010;
            4'd3: seg <= 8'b11110010;
            4'd4: seg <= 8'b01100110;
            4'd5: seg <= 8'b10110110;
            4'd6: seg <= 8'b11000110;
            4'd7: seg <= 8'b00111010;
            4'd8: seg <= 8'b00000000;
            default: seg <= 8'b00000000;
        endcase
    end
endmodule

module lift_ctrl(
    input clk_100m,
    input reset_n,
    input BTN2, BTN1, BTN0,
    output reg [7:0] seg_out,
    output reg [3:0] com_out,
    output [3:0] motor_out
);
    reg [30:0] sec_cnt;
    reg [2:0] wait_tick;

    reg [3:0] seg_timer, seg_dir, seg_floor;
    reg mtr_on, mtr_dir;

    reg [2:0] cur_state;
    localparam ST_IDLE = 3'd0, ST_MOVE = 3'd1, ST_END_MOVE = 3'd2, ST_WAIT_IDLE = 3'd3;

    localparam INIT_COUNT = 4'd5;
    localparam SEG_OFF = 4'd8;
    localparam FL_1F = 4'd1, FL_2F = 4'd2;
    localparam DIR_UP = 4'd6, DIR_DOWN = 4'd7;

    reg [1:0] btn0_sync, btn1_sync, btn2_sync;

    always @(posedge clk_100m or negedge reset_n) begin
        if (!reset_n) begin
            btn0_sync <= 2'b11; btn1_sync <= 2'b11; btn2_sync <= 2'b11;
        end else begin
            btn0_sync <= {btn0_sync[0], BTN0};
            btn1_sync <= {btn1_sync[0], BTN1};
            btn2_sync <= {btn2_sync[0], BTN2};
        end
    end

    wire btn0_rise = (btn0_sync[1] == 0 && btn0_sync[0] == 1);
    wire btn1_rise = (btn1_sync[1] == 0 && btn1_sync[0] == 1);
    wire btn2_rise = (btn2_sync[1] == 0 && btn2_sync[0] == 1);

    always @(posedge clk_100m or negedge reset_n) begin
        if (!reset_n) begin
            mtr_on <= 0; mtr_dir <= 0; sec_cnt <= 0;
            seg_timer <= INIT_COUNT; seg_dir <= SEG_OFF; seg_floor <= FL_1F;
            cur_state <= ST_IDLE;
        end else begin
            case (cur_state)
                ST_IDLE: begin
                    if (btn2_rise) begin
                        seg_timer <= INIT_COUNT;
                        cur_state <= ST_IDLE;
                    end
                    if (btn0_rise && seg_floor != FL_1F) begin
                        seg_timer <= INIT_COUNT; seg_dir <= DIR_DOWN; seg_floor <= FL_2F;
                        sec_cnt <= 0; mtr_on <= 1; mtr_dir <= 0; cur_state <= ST_MOVE;
                    end else if (btn1_rise && seg_floor != FL_2F) begin
                        seg_timer <= INIT_COUNT; seg_dir <= DIR_UP; seg_floor <= FL_1F;
                        sec_cnt <= 0; mtr_on <= 1; mtr_dir <= 1; cur_state <= ST_MOVE;
                    end
                end
                ST_MOVE: begin
                    if (sec_cnt >= 500_000_000) begin
                        sec_cnt <= 0; seg_timer <= INIT_COUNT; wait_tick <= 0;
                        mtr_on <= 0; cur_state <= ST_END_MOVE;
                    end else begin
                        sec_cnt <= sec_cnt + 1;
                    end
                end
                ST_END_MOVE: begin
                    seg_timer <= INIT_COUNT;
                    if (seg_dir == DIR_DOWN) begin
                        seg_dir <= 4'd0; seg_floor <= FL_1F;
                    end else if (seg_dir == DIR_UP) begin
                        seg_dir <= 4'd0; seg_floor <= FL_2F;
                    end else cur_state <= ST_WAIT_IDLE;
                end
                ST_WAIT_IDLE: begin
                    if (btn2_rise) begin
                        seg_timer <= INIT_COUNT;
                        cur_state <= ST_IDLE;
                    end else if (sec_cnt >= 100_000_000) begin
                        sec_cnt <= 0;
                        if (wait_tick < 4) begin
                            seg_timer <= seg_timer - 1; wait_tick <= wait_tick + 1;
                        end else cur_state <= ST_IDLE;
                    end else begin
                        sec_cnt <= sec_cnt + 1;
                    end
                end
            endcase
        end
    end

    wire [3:0] seg0_code = SEG_OFF;
    wire [7:0] seg0, seg1, seg2, seg3;
    seg_encoder u0(.code(seg0_code), .seg(seg0));
    seg_encoder u1(.code(seg_timer), .seg(seg1));
    seg_encoder u2(.code(seg_dir), .seg(seg2));
    seg_encoder u3(.code(seg_floor), .seg(seg3));

    reg [19:0] fnd_cnt;
    reg [1:0] fnd_sel;
    always @(posedge clk_100m or negedge reset_n) begin
        if (!reset_n) begin
            fnd_cnt <= 0; fnd_sel <= 0;
        end else if (fnd_cnt < 200_000) begin
            fnd_cnt <= fnd_cnt + 1;
        end else begin
            fnd_cnt <= 0; fnd_sel <= fnd_sel + 1;
        end
    end

    always @(*) begin
        case (fnd_sel)
            2'd0: begin seg_out = seg0; com_out = 4'b1110; end
            2'd1: begin seg_out = seg1; com_out = 4'b1101; end
            2'd2: begin seg_out = seg2; com_out = 4'b1011; end
            2'd3: begin seg_out = seg3; com_out = 4'b0111; end
            default: begin seg_out = 8'b00000000; com_out = 4'b1111; end
        endcase
    end

    step_driver motor_unit(
        .clk(clk_100m), .reset_n(reset_n), .motor_enable(mtr_on),
        .motor_dir(mtr_dir), .motor_out(motor_out)
    );

endmodule

module step_driver(
    input clk,
    input reset_n,
    input motor_enable,
    input motor_dir,
    output reg [3:0] motor_out
);
    reg [25:0] mtr_cnt;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            motor_out <= 4'b0000; mtr_cnt <= 0;
        end else if (motor_enable) begin
            if (mtr_cnt > 2_000_000) mtr_cnt <= 0;
            else mtr_cnt <= mtr_cnt + 1;

            case (mtr_cnt)
                0:        motor_out <= (motor_dir) ? 4'b1001 : 4'b1100;
                500000:   motor_out <= (motor_dir) ? 4'b1100 : 4'b1001;
                1000000:  motor_out <= (motor_dir) ? 4'b0110 : 4'b0011;
                1500000:  motor_out <= (motor_dir) ? 4'b0011 : 4'b0110;
                default:  motor_out <= motor_out;
            endcase
        end else begin
            motor_out <= 4'b0000; mtr_cnt <= 0;
        end
    end
endmodule
