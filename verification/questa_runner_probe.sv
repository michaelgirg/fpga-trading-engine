`timescale 1ns/1ps
module questa_runner_probe #(parameter int MODE = 0);
    int failed = 0;
    initial begin
        $display("RUNNER PROBE mode=%0d", MODE);
        #1;
        case (MODE)
            0: $finish;
            1: begin
                failed++;
                $display("Tests failed: %0d", failed);
                if (failed == 0) $finish;
                else $fatal(1, "injected scoreboard failure");
            end
            2: $fatal(1, "injected fatal failure");
            3: forever #1;
            4: $stop;
        endcase
    end
endmodule
