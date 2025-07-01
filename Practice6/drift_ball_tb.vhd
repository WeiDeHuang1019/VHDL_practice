library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_drift_ball is
end tb_drift_ball;

architecture sim of tb_drift_ball is
    -- 宣告 DUT 的介面
    signal i_clk  : STD_LOGIC := '0';
    signal i_rst  : STD_LOGIC := '0';
    signal o_led  : STD_LOGIC_VECTOR(7 downto 0);

    -- 時脈週期
    constant clk_period : time := 10 ns;  -- 100 MHz clock
begin

    -- 時脈產生器
    clk_process : process
    begin
        while now < 2 ms loop
            i_clk <= '0';
            wait for clk_period / 2;
            i_clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;

    -- 測試序列
    stim_proc: process
    begin
        -- 初始 Reset
        i_rst <= '0';
        wait for 100 ns;
        i_rst <= '1';

        -- 模擬觀察時間
        wait for 2 ms;

        wait;
    end process;

    -- DUT 實體化
    uut: entity work.drift_ball
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            o_led => o_led
        );

end sim;
